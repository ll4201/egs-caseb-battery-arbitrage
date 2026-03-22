function solution = solve_caseB_stacking_lp(model, data, params)
% solve_caseB_stacking_lp
% Solve the Case B market stacking LP using MATLAB linprog.
%
% INPUTS:
%   model   - struct returned by build_caseB_stacking_lp
%   data    - struct returned by read_caseB_data
%   params  - parameter struct from main script
%
% OUTPUT:
%   solution - struct containing optimisation results:
%       solution.x
%       solution.exitflag
%       solution.output
%       solution.lambda
%       solution.fval
%       solution.Pch
%       solution.Pdis
%       solution.SOC
%       solution.R
%       solution.arbitrage_revenue_gbp
%       solution.ancillary_revenue_gbp
%       solution.total_revenue_gbp
%       solution.objective_value
%       solution.solver_name
%
% Notes:
% - linprog solves:
%       min f' * x
%   while our original problem is:
%       max total stacked revenue
%   Hence:
%       total_revenue_gbp = -fval

    %% 1. Basic input checks
    requiredModelFields = {'f', 'A', 'b', 'Aeq', 'beq', 'lb', 'ub', 'idx'};
    for i = 1:numel(requiredModelFields)
        if ~isfield(model, requiredModelFields{i})
            error('solve_caseB_stacking_lp:MissingModelField', ...
                'Missing required field model.%s', requiredModelFields{i});
        end
    end

    requiredDataFields = {'N', 'dt', 'price_kwh', 'ancillary_price_mw_h'};
    for i = 1:numel(requiredDataFields)
        if ~isfield(data, requiredDataFields{i})
            error('solve_caseB_stacking_lp:MissingDataField', ...
                'Missing required field data.%s', requiredDataFields{i});
        end
    end

    requiredParamFields = {'SOC_init', 'terminalMode'};
    for i = 1:numel(requiredParamFields)
        if ~isfield(params, requiredParamFields{i})
            error('solve_caseB_stacking_lp:MissingParamField', ...
                'Missing required field params.%s', requiredParamFields{i});
        end
    end

    N = data.N;
    dt = data.dt;

    price_DA = data.price_kwh(:);                % GBP/kWh
    price_anc = data.ancillary_price_mw_h(:);    % GBP/MW/h

    %% 2. Prepare LP inputs
    f   = model.f;
    A   = model.A;
    b   = model.b;
    Aeq = model.Aeq;
    beq = model.beq;
    lb  = model.lb;
    ub  = model.ub;

    if isempty(A)
        A = [];
        b = [];
    end

    if isempty(Aeq)
        error('solve_caseB_stacking_lp:MissingEqualityConstraints', ...
            'Aeq/beq should not be empty for this model.');
    end

    %% 3. Solver options
    options = optimoptions('linprog', ...
        'Algorithm', 'dual-simplex', ...
        'Display', 'iter');

    fprintf('\n--- Solving stacking LP with linprog ---\n');
    fprintf('Algorithm: dual-simplex\n');
    fprintf('Number of variables: %d\n', numel(f));
    fprintf('Number of equality constraints: %d\n', size(Aeq, 1));
    fprintf('Number of inequality constraints: %d\n', size(A, 1));
    fprintf('----------------------------------------\n\n');

    %% 4. Solve LP
    [x, fval, exitflag, output, lambda] = linprog( ...
        f, A, b, Aeq, beq, lb, ub, options);

    %% 5. Handle solver result
    if isempty(x)
        warning('solve_caseB_stacking_lp:EmptySolution', ...
            'linprog returned an empty solution vector.');

        solution = struct();
        solution.x = [];
        solution.exitflag = exitflag;
        solution.output = output;
        solution.lambda = [];
        solution.fval = [];
        solution.Pch = [];
        solution.Pdis = [];
        solution.SOC = [];
        solution.R = [];
        solution.arbitrage_revenue_gbp = [];
        solution.ancillary_revenue_gbp = [];
        solution.total_revenue_gbp = [];
        solution.objective_value = [];
        solution.solver_name = 'linprog';
        return;
    end

    %% 6. Extract decision variables
    Pch  = x(model.idx.Pch);
    Pdis = x(model.idx.Pdis);
    SOC  = x(model.idx.SOC);
    R    = x(model.idx.R);

    if numel(Pch) ~= N || numel(Pdis) ~= N || numel(SOC) ~= N || numel(R) ~= N
        error('solve_caseB_stacking_lp:SolutionDimensionMismatch', ...
            'Extracted solution dimensions do not match data.N.');
    end

    %% 7. Recover revenue components
    % Arbitrage revenue:
    % sum_t price_DA(t) * (Pdis(t) - Pch(t)) * dt
    arbitrage_revenue_each_step_gbp = price_DA .* (Pdis - Pch) * dt;
    arbitrage_revenue_gbp = sum(arbitrage_revenue_each_step_gbp);

    % Ancillary revenue:
    % sum_t price_anc(t) * (R(t)/1000) * dt
    ancillary_revenue_each_step_gbp = price_anc .* (R / 1000) * dt;
    ancillary_revenue_gbp = sum(ancillary_revenue_each_step_gbp);

    % Total stacked revenue
    total_revenue_gbp = arbitrage_revenue_gbp + ancillary_revenue_gbp;

    % linprog minimises negative revenue
    recovered_total_revenue_from_fval = -fval;

    %% 8. Pack outputs
    solution = struct();
    solution.x = x;
    solution.exitflag = exitflag;
    solution.output = output;
    solution.lambda = lambda;
    solution.fval = fval;

    solution.Pch = Pch;
    solution.Pdis = Pdis;
    solution.SOC = SOC;
    solution.R = R;

    solution.arbitrage_revenue_each_step_gbp = arbitrage_revenue_each_step_gbp;
    solution.ancillary_revenue_each_step_gbp = ancillary_revenue_each_step_gbp;

    solution.arbitrage_revenue_gbp = arbitrage_revenue_gbp;
    solution.ancillary_revenue_gbp = ancillary_revenue_gbp;
    solution.total_revenue_gbp = total_revenue_gbp;
    solution.recovered_total_revenue_from_fval = recovered_total_revenue_from_fval;

    solution.objective_value = fval;
    solution.solver_name = 'linprog';

    %% 9. Additional diagnostics
    tol = 1e-8;

    solution.charge_hours = sum(Pch > tol);
    solution.discharge_hours = sum(Pdis > tol);
    solution.reserve_active_hours = sum(R > tol);
    solution.idle_hours = sum((Pch <= tol) & (Pdis <= tol) & (R <= tol));

    solution.simultaneous_charge_discharge_hours = sum((Pch > tol) & (Pdis > tol));
    solution.simultaneous_charge_reserve_hours = sum((Pch > tol) & (R > tol));
    solution.simultaneous_discharge_reserve_hours = sum((Pdis > tol) & (R > tol));

    solution.avg_reserved_capacity_kw = mean(R);
    solution.max_reserved_capacity_kw = max(R);

    % Capacity sharing slack (useful for verification/debugging)
    solution.charge_reserve_headroom_kw = params.Pch_max - (Pch + R);
    solution.discharge_reserve_headroom_kw = params.Pdis_max - (Pdis + R);

    %% 10. Revenue breakdown shares
    if abs(total_revenue_gbp) > 0
        solution.arbitrage_revenue_share = arbitrage_revenue_gbp / total_revenue_gbp;
        solution.ancillary_revenue_share = ancillary_revenue_gbp / total_revenue_gbp;
    else
        solution.arbitrage_revenue_share = NaN;
        solution.ancillary_revenue_share = NaN;
    end

    %% 11. Print summary
    fprintf('\n--- Stacking LP solve summary ---\n');
    fprintf('Exit flag                        : %d\n', exitflag);

    if isfield(output, 'message')
        fprintf('Solver message                   : %s\n', strtrim(output.message));
    end

    fprintf('Objective value (min form)       : %.6f\n', fval);
    fprintf('Recovered total revenue          : %.6f GBP\n', recovered_total_revenue_from_fval);
    fprintf('Recomputed total revenue         : %.6f GBP\n', total_revenue_gbp);
    fprintf('  Arbitrage revenue              : %.6f GBP\n', arbitrage_revenue_gbp);
    fprintf('  Ancillary revenue              : %.6f GBP\n', ancillary_revenue_gbp);

    fprintf('Charge-active hours              : %d\n', solution.charge_hours);
    fprintf('Discharge-active hours           : %d\n', solution.discharge_hours);
    fprintf('Reserve-active hours             : %d\n', solution.reserve_active_hours);
    fprintf('Idle hours                       : %d\n', solution.idle_hours);

    fprintf('Simultaneous ch/dis hours        : %d\n', ...
        solution.simultaneous_charge_discharge_hours);
    fprintf('Simultaneous ch/reserve hours    : %d\n', ...
        solution.simultaneous_charge_reserve_hours);
    fprintf('Simultaneous dis/reserve hours   : %d\n', ...
        solution.simultaneous_discharge_reserve_hours);

    fprintf('Average reserved capacity        : %.6f kW\n', ...
        solution.avg_reserved_capacity_kw);
    fprintf('Maximum reserved capacity        : %.6f kW\n', ...
        solution.max_reserved_capacity_kw);

    fprintf('Initial SOC from solution        : %.6f kWh\n', SOC(1));
    fprintf('Final SOC from solution          : %.6f kWh\n', SOC(end));
    fprintf('Terminal mode                    : %s\n', params.terminalMode);

    if exitflag <= 0
        warning('solve_caseB_stacking_lp:NonOptimalExit', ...
            ['linprog did not report a standard successful optimal solve. ', ...
             'Check output.message for details.']);
    end

    fprintf('----------------------------------\n\n');
end