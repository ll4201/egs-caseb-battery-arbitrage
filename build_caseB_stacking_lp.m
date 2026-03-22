function model = build_caseB_stacking_lp(data, params)
% build_caseB_stacking_lp
% Construct the linear programming model for Case B extension:
% energy arbitrage + ancillary market stacking via capacity reservation.
%
% Decision variables:
%   x = [Pch(1:N);
%        Pdis(1:N);
%        SOC(1:N);
%        R(1:N)]
%
% where:
%   Pch(t)   = charging power at time t [kW]
%   Pdis(t)  = discharging power at time t [kW]
%   SOC(t)   = state of charge at time t [kWh]
%   R(t)     = ancillary reserve capacity at time t [kW]
%
% Objective:
%   Maximise total stacked revenue:
%
%   sum_t [ price_DA(t) * (Pdis(t) - Pch(t)) * dt
%         + price_anc(t) * (R(t)/1000) * dt ]
%
% where:
%   price_DA(t)   is in GBP/kWh
%   price_anc(t)  is in GBP/MW/h
%
% Since linprog performs minimisation, we solve:
%   Minimise negative total revenue
%
% Additional stacking constraints:
%   Pch(t)  + R(t) <= Pch_max
%   Pdis(t) + R(t) <= Pdis_max
%
% Inputs:
%   data.price_kwh                 [N x 1] day-ahead price [GBP/kWh]
%   data.ancillary_price_mw_h      [N x 1] ancillary availability price [GBP/MW/h]
%   data.N
%   data.dt
%
%   params.Emax
%   params.Pch_max
%   params.Pdis_max
%   params.eta_ch
%   params.eta_dis
%   params.SOC_init
%   params.terminalMode            'equal' or 'greater_equal'
%
% Optional params:
%   params.R_max                   reserve capacity upper bound [kW]
%                                  if absent, defaults to min(Pch_max,Pdis_max)
%
% Output:
%   model structure containing:
%       f, A, b, Aeq, beq, lb, ub
%       idx
%       meta

    %% 1. Basic input checks
    requiredDataFields = {'price_kwh', 'ancillary_price_mw_h', 'N', 'dt'};
    for i = 1:numel(requiredDataFields)
        if ~isfield(data, requiredDataFields{i})
            error('build_caseB_stacking_lp:MissingDataField', ...
                'Missing required field data.%s', requiredDataFields{i});
        end
    end

    requiredParamFields = {'Emax', 'Pch_max', 'Pdis_max', ...
                           'eta_ch', 'eta_dis', 'SOC_init', 'terminalMode'};
    for i = 1:numel(requiredParamFields)
        if ~isfield(params, requiredParamFields{i})
            error('build_caseB_stacking_lp:MissingParamField', ...
                'Missing required field params.%s', requiredParamFields{i});
        end
    end

    N = data.N;
    dt = data.dt;

    price_DA = data.price_kwh(:);                % GBP/kWh
    price_anc = data.ancillary_price_mw_h(:);    % GBP/MW/h

    if numel(price_DA) ~= N
        error('build_caseB_stacking_lp:DimensionMismatch', ...
            'Length of data.price_kwh (%d) does not match data.N (%d).', ...
            numel(price_DA), N);
    end

    if numel(price_anc) ~= N
        error('build_caseB_stacking_lp:DimensionMismatch', ...
            'Length of data.ancillary_price_mw_h (%d) does not match data.N (%d).', ...
            numel(price_anc), N);
    end

    if any(~isfinite(price_DA))
        error('build_caseB_stacking_lp:InvalidDayAheadPrice', ...
            'data.price_kwh contains non-finite values.');
    end

    if any(~isfinite(price_anc))
        error('build_caseB_stacking_lp:InvalidAncillaryPrice', ...
            'data.ancillary_price_mw_h contains non-finite values.');
    end

    if N < 2
        error('build_caseB_stacking_lp:TooFewSteps', ...
            'At least 2 time steps are required to build the LP model.');
    end

    if dt <= 0
        error('build_caseB_stacking_lp:InvalidDt', ...
            'Time step dt must be positive.');
    end

    if params.Emax <= 0 || params.Pch_max < 0 || params.Pdis_max < 0
        error('build_caseB_stacking_lp:InvalidBatteryParameters', ...
            'Battery capacity and power limits must be non-negative, with Emax > 0.');
    end

    if params.eta_ch <= 0 || params.eta_ch > 1 || ...
       params.eta_dis <= 0 || params.eta_dis > 1
        error('build_caseB_stacking_lp:InvalidEfficiency', ...
            'Charge/discharge efficiencies must lie in (0, 1].');
    end

    if params.SOC_init < 0 || params.SOC_init > params.Emax
        error('build_caseB_stacking_lp:InvalidInitialSOC', ...
            'Initial SOC must lie within [0, Emax].');
    end

    %% 2. Reserve upper bound
    if isfield(params, 'R_max') && ~isempty(params.R_max)
        R_max = params.R_max;
    else
        R_max = min(params.Pch_max, params.Pdis_max);
    end

    if R_max < 0
        error('build_caseB_stacking_lp:InvalidReserveBound', ...
            'Reserve upper bound R_max must be non-negative.');
    end

    %% 3. Variable indexing
    % x = [Pch(1:N), Pdis(1:N), SOC(1:N), R(1:N)]'
    nPch = N;
    nPdis = N;
    nSOC = N;
    nR = N;

    idx = struct();
    idx.Pch = 1:nPch;
    idx.Pdis = (nPch + 1):(nPch + nPdis);
    idx.SOC = (nPch + nPdis + 1):(nPch + nPdis + nSOC);
    idx.R   = (nPch + nPdis + nSOC + 1):(nPch + nPdis + nSOC + nR);

    nVars = nPch + nPdis + nSOC + nR;

    %% 4. Objective function
    % Total revenue:
    %
    % Revenue_DA = sum_t price_DA(t) * (Pdis(t) - Pch(t)) * dt
    %
    % Revenue_anc = sum_t price_anc(t) * (R(t)/1000) * dt
    %
    % linprog minimises:
    %   f' * x = - (Revenue_DA + Revenue_anc)
    %
    % Therefore:
    %   f(Pch)  = +price_DA * dt
    %   f(Pdis) = -price_DA * dt
    %   f(SOC)  = 0
    %   f(R)    = -(price_anc/1000) * dt

    f = zeros(nVars, 1);
    f(idx.Pch)  =  price_DA * dt;
    f(idx.Pdis) = -price_DA * dt;
    f(idx.SOC)  =  0;
    f(idx.R)    = -(price_anc / 1000) * dt;

    %% 5. Equality constraints
    % (a) SOC(1) = SOC_init
    % (b) SOC dynamics:
    %     SOC(t+1) - SOC(t) - eta_ch*dt*Pch(t) + (dt/eta_dis)*Pdis(t) = 0
    %     for t = 1,...,N-1
    %
    % If terminalMode == 'equal':
    % (c) SOC(N) = SOC_init

    nDynEq = N - 1;
    useTerminalEquality = strcmpi(params.terminalMode, 'equal');

    nEq = 1 + nDynEq + double(useTerminalEquality);

    Aeq = zeros(nEq, nVars);
    beq = zeros(nEq, 1);

    row = 1;

    % (a) Initial SOC equality
    Aeq(row, idx.SOC(1)) = 1;
    beq(row) = params.SOC_init;
    row = row + 1;

    % (b) SOC dynamics
    for t = 1:(N - 1)
        Aeq(row, idx.SOC(t + 1)) =  1;
        Aeq(row, idx.SOC(t))     = -1;
        Aeq(row, idx.Pch(t))     = -params.eta_ch * dt;
        Aeq(row, idx.Pdis(t))    =  dt / params.eta_dis;
        beq(row) = 0;
        row = row + 1;
    end

    % (c) Terminal SOC equality if required
    if useTerminalEquality
        Aeq(row, idx.SOC(N)) = 1;
        beq(row) = params.SOC_init;
    end

    %% 6. Inequality constraints
    % Base-case terminal inequality if needed:
    %   SOC(N) >= SOC_init  ->  -SOC(N) <= -SOC_init
    %
    % New stacking constraints:
    %   Pch(t)  + R(t) <= Pch_max
    %   Pdis(t) + R(t) <= Pdis_max
    %
    % Total number of inequality constraints:
    %   0 or 1  terminal inequality
    %   + N     charge-reserve sharing
    %   + N     discharge-reserve sharing

    hasTerminalGE = strcmpi(params.terminalMode, 'greater_equal');
    if ~hasTerminalGE && ~strcmpi(params.terminalMode, 'equal')
        error('build_caseB_stacking_lp:InvalidTerminalMode', ...
            'params.terminalMode must be either ''equal'' or ''greater_equal''.');
    end

    nIneq = double(hasTerminalGE) + N + N;
    A = zeros(nIneq, nVars);
    b = zeros(nIneq, 1);

    row = 1;

    % Terminal SOC inequality if needed
    if hasTerminalGE
        A(row, idx.SOC(N)) = -1;
        b(row) = -params.SOC_init;
        row = row + 1;
    end

    % Charge-reserve sharing:
    %   Pch(t) + R(t) <= Pch_max
    for t = 1:N
        A(row, idx.Pch(t)) = 1;
        A(row, idx.R(t))   = 1;
        b(row) = params.Pch_max;
        row = row + 1;
    end

    % Discharge-reserve sharing:
    %   Pdis(t) + R(t) <= Pdis_max
    for t = 1:N
        A(row, idx.Pdis(t)) = 1;
        A(row, idx.R(t))    = 1;
        b(row) = params.Pdis_max;
        row = row + 1;
    end

    %% 7. Variable bounds
    lb = zeros(nVars, 1);
    ub = inf(nVars, 1);

    % Charging power bounds
    lb(idx.Pch) = 0;
    ub(idx.Pch) = params.Pch_max;

    % Discharging power bounds
    lb(idx.Pdis) = 0;
    ub(idx.Pdis) = params.Pdis_max;

    % SOC bounds
    lb(idx.SOC) = 0;
    ub(idx.SOC) = params.Emax;

    % Reserve bounds
    lb(idx.R) = 0;
    ub(idx.R) = R_max;

    %% 8. Notes on modelling assumptions
    % Assumption 1:
    % Reserve is modelled as capacity reservation revenue only.
    % It does not directly alter SOC because no activation energy is modelled.
    %
    % Assumption 2:
    % Reserve competes with both charging and discharging headroom via:
    %   Pch + R <= Pch_max
    %   Pdis + R <= Pdis_max
    %
    % This is a conservative but linear and interpretable stacking formulation.
    %
    % Assumption 3:
    % As in the base case, simultaneous charging/discharging is not explicitly
    % forbidden by integer logic, but it can later be checked in verification.

    %% 9. Store outputs
    model = struct();

    model.f = f;
    model.A = A;
    model.b = b;
    model.Aeq = Aeq;
    model.beq = beq;
    model.lb = lb;
    model.ub = ub;

    model.idx = idx;

    model.meta = struct();
    model.meta.nVars = nVars;
    model.meta.N = N;
    model.meta.dt = dt;
    model.meta.R_max = R_max;
    model.meta.variableOrder = '[Pch(1:N), Pdis(1:N), SOC(1:N), R(1:N)]';
    model.meta.objectiveType = 'Minimise negative stacked revenue';
    model.meta.terminalMode = params.terminalMode;
    model.meta.useTerminalEquality = useTerminalEquality;
    model.meta.reserveModel = 'Capacity reservation revenue (no activation energy)';
    model.meta.ancillaryPriceUnit = 'GBP/MW/h';
    model.meta.reserveVariableUnit = 'kW';

    %% 10. Print summary
    fprintf('\n--- Stacking LP model summary ---\n');
    fprintf('Time steps N                  : %d\n', N);
    fprintf('Decision variables            : %d\n', nVars);
    fprintf('  Pch variables               : %d\n', nPch);
    fprintf('  Pdis variables              : %d\n', nPdis);
    fprintf('  SOC variables               : %d\n', nSOC);
    fprintf('  Reserve variables           : %d\n', nR);
    fprintf('Equality constraints          : %d\n', size(Aeq, 1));
    fprintf('Inequality constraints        : %d\n', size(A, 1));
    fprintf('Terminal SOC mode             : %s\n', params.terminalMode);
    fprintf('Reserve upper bound R_max     : %.4f kW\n', R_max);
    fprintf('Ancillary price unit          : GBP/MW/h\n');
    fprintf('Reserve variable unit         : kW\n');
    fprintf('Objective                     : maximise arbitrage + ancillary revenue\n');
    fprintf('---------------------------------\n\n');
end