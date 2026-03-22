function model = build_caseB_lp(data, params)
% build_caseB_lp
% Construct the linear programming model for Case B:
% grid-scale battery arbitrage in the day-ahead electricity market.
%
% Decision variables:
%   x = [Pch(1:N);
%        Pdis(1:N);
%        SOC(1:N)]
%
% where:
%   Pch(t)   = charging power at time t [kW]
%   Pdis(t)  = discharging power at time t [kW]
%   SOC(t)   = state of charge at time t [kWh]
%
% Objective:
%   Maximise profit = sum_t price(t) * (Pdis(t) - Pch(t)) * dt
%
% Since linprog performs minimisation, we solve:
%   Minimise -profit
%
% Inputs:
%   data.price_kwh   [N x 1] day-ahead price [GBP/kWh]
%   data.N           number of time steps
%   data.dt          time step [h]
%
%   params.Emax
%   params.Pch_max
%   params.Pdis_max
%   params.eta_ch
%   params.eta_dis
%   params.SOC_init
%   params.terminalMode   'equal' or 'greater_equal'
%
% Output:
%   model structure containing:
%       f, A, b, Aeq, beq, lb, ub
%       idx
%       meta

    %% 1. Basic input checks
    requiredDataFields = {'price_kwh', 'N', 'dt'};
    for i = 1:numel(requiredDataFields)
        if ~isfield(data, requiredDataFields{i})
            error('build_caseB_lp:MissingDataField', ...
                'Missing required field data.%s', requiredDataFields{i});
        end
    end

    requiredParamFields = {'Emax', 'Pch_max', 'Pdis_max', ...
                           'eta_ch', 'eta_dis', 'SOC_init', 'terminalMode'};
    for i = 1:numel(requiredParamFields)
        if ~isfield(params, requiredParamFields{i})
            error('build_caseB_lp:MissingParamField', ...
                'Missing required field params.%s', requiredParamFields{i});
        end
    end

    N = data.N;
    dt = data.dt;
    price = data.price_kwh(:);

    if numel(price) ~= N
        error('build_caseB_lp:DimensionMismatch', ...
            'Length of data.price_kwh (%d) does not match data.N (%d).', ...
            numel(price), N);
    end

    if N < 2
        error('build_caseB_lp:TooFewSteps', ...
            'At least 2 time steps are required to build the LP model.');
    end

    if dt <= 0
        error('build_caseB_lp:InvalidDt', ...
            'Time step dt must be positive.');
    end

    if params.Emax <= 0 || params.Pch_max < 0 || params.Pdis_max < 0
        error('build_caseB_lp:InvalidBatteryParameters', ...
            'Battery capacity and power limits must be non-negative, with Emax > 0.');
    end

    if params.eta_ch <= 0 || params.eta_ch > 1 || ...
       params.eta_dis <= 0 || params.eta_dis > 1
        error('build_caseB_lp:InvalidEfficiency', ...
            'Charge/discharge efficiencies must lie in (0, 1].');
    end

    if params.SOC_init < 0 || params.SOC_init > params.Emax
        error('build_caseB_lp:InvalidInitialSOC', ...
            'Initial SOC must lie within [0, Emax].');
    end

    %% 2. Variable indexing
    % x = [Pch(1:N), Pdis(1:N), SOC(1:N)]'
    nPch = N;
    nPdis = N;
    nSOC = N;

    idx = struct();
    idx.Pch = 1:nPch;
    idx.Pdis = (nPch + 1):(nPch + nPdis);
    idx.SOC = (nPch + nPdis + 1):(nPch + nPdis + nSOC);

    nVars = nPch + nPdis + nSOC;

    %% 3. Objective function
    % Profit = sum_t price(t) * (Pdis(t) - Pch(t)) * dt
    %
    % linprog solves minimisation:
    % minimise f' * x = -profit
    %
    % Therefore:
    %   f(Pch)  = +price*dt
    %   f(Pdis) = -price*dt
    %   f(SOC)  = 0

    f = zeros(nVars, 1);
    f(idx.Pch)  =  price * dt;
    f(idx.Pdis) = -price * dt;
    f(idx.SOC)  =  0;

    %% 4. Equality constraints
    % We impose:
    %   (a) SOC(1) = SOC_init
    %   (b) SOC(t+1) - SOC(t) - eta_ch*dt*Pch(t) + (dt/eta_dis)*Pdis(t) = 0
    %       for t = 1, ..., N-1
    %
    % If terminalMode == 'equal', also impose:
    %   (c) SOC(N) = SOC_init

    nDynEq = N - 1;
    useTerminalEquality = strcmpi(params.terminalMode, 'equal');

    nEq = 1 + nDynEq + double(useTerminalEquality);

    Aeq = zeros(nEq, nVars);
    beq = zeros(nEq, 1);

    row = 1;

    % (a) Initial SOC equality: SOC(1) = SOC_init
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

    % (c) Terminal SOC equality, if required
    if useTerminalEquality
        Aeq(row, idx.SOC(N)) = 1;
        beq(row) = params.SOC_init;
    end

    %% 5. Inequality constraints
    % If terminalMode == 'greater_equal', impose:
    %   SOC(N) >= SOC_init
    %
    % Standard linprog form is A*x <= b
    % so:
    %   -SOC(N) <= -SOC_init

    A = [];
    b = [];

    if strcmpi(params.terminalMode, 'greater_equal')
        A = zeros(1, nVars);
        b = zeros(1, 1);

        A(1, idx.SOC(N)) = -1;
        b(1) = -params.SOC_init;
    elseif ~strcmpi(params.terminalMode, 'equal')
        error('build_caseB_lp:InvalidTerminalMode', ...
            'params.terminalMode must be either ''equal'' or ''greater_equal''.');
    end

    %% 6. Variable bounds
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

    %% 7. Optional note on simultaneous charge/discharge
    % In a strict physical sense, one may want:
    %   Pch(t) * Pdis(t) = 0
    % for all t
    %
    % However, that is non-linear and would turn the LP into a more complex problem.
    % For this coursework base case, we keep the model linear.
    %
    % In practice, because:
    %   - charging and discharging both incur efficiency losses
    %   - the same price is used for buy/sell in the day-ahead arbitrage objective
    % simultaneous charge and discharge is usually unattractive economically.
    %
    % If needed, this behaviour can later be checked in verification.

    %% 8. Store model outputs
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
    model.meta.variableOrder = '[Pch(1:N), Pdis(1:N), SOC(1:N)]';
    model.meta.objectiveType = 'Minimise negative arbitrage profit';
    model.meta.terminalMode = params.terminalMode;
    model.meta.useTerminalEquality = useTerminalEquality;

    %% 9. Print summary
    fprintf('\n--- LP model summary ---\n');
    fprintf('Time steps N              : %d\n', N);
    fprintf('Decision variables        : %d\n', nVars);
    fprintf('  Pch variables           : %d\n', nPch);
    fprintf('  Pdis variables          : %d\n', nPdis);
    fprintf('  SOC variables           : %d\n', nSOC);
    fprintf('Equality constraints      : %d\n', size(Aeq, 1));
    fprintf('Inequality constraints    : %d\n', size(A, 1));
    fprintf('Terminal SOC mode         : %s\n', params.terminalMode);
    fprintf('Objective                 : maximise arbitrage profit\n');
    fprintf('-------------------------\n\n');
end