function solution = solve_caseB_lp(model, data, params)
% solve_caseB_lp
% Solve the Case B battery arbitrage LP using MATLAB linprog.
%
% INPUTS:
%   model   - struct returned by build_caseB_lp
%   data    - struct returned by read_caseB_data
%   params  - parameter struct from main_caseB
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
%       solution.profit_opt
%       solution.objective_value
%       solution.solver_name
%
% Notes:
% - linprog solves:
%       min f' * x
%   while our original problem is:
%       max profit
%   Hence:
%       profit_opt = -fval

    %% 1. Basic input checks
    requiredModelFields = {'f', 'A', 'b', 'Aeq', 'beq', 'lb', 'ub', 'idx'};
    for i = 1:numel(requiredModelFields)
        if ~isfield(model, requiredModelFields{i})
            error('solve_caseB_lp:MissingModelField', ...
                'Missing required field model.%s', requiredModelFields{i});
        end
    end

    requiredDataFields = {'N', 'price_kwh', 'dt'};
    for i = 1:numel(requiredDataFields)
        if ~isfield(data, requiredDataFields{i})
            error('solve_caseB_lp:MissingDataField', ...
                'Missing required field data.%s', requiredDataFields{i});
        end
    end

    requiredParamFields = {'SOC_init', 'terminalMode'};
    for i = 1:numel(requiredParamFields)
        if ~isfield(params, requiredParamFields{i})
            error('solve_caseB_lp:MissingParamField', ...
                'Missing required field params.%s', requiredParamFields{i});
        end
    end

    N = data.N;

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
        error('solve_caseB_lp:MissingEqualityConstraints', ...
            'Aeq/beq should not be empty for this model.');
    end

    %% 3. Solver options
    % Dual-simplex is usually robust for LPs of this kind
    options = optimoptions('linprog', ...
        'Algorithm', 'dual-simplex', ...
        'Display', 'iter');

    fprintf('\n--- Solving LP with linprog ---\n');
    fprintf('Algorithm: dual-simplex\n');
    fprintf('Number of variables: %d\n', numel(f));
    fprintf('Number of equality constraints: %d\n', size(Aeq, 1));
    fprintf('Number of inequality constraints: %d\n', size(A, 1));
    fprintf('--------------------------------\n\n');

    %% 4. Solve LP
    [x, fval, exitflag, output, lambda] = linprog( ...
        f, A, b, Aeq, beq, lb, ub, options);

    %% 5. Handle solver result
    if isempty(x)
        warning('solve_caseB_lp:EmptySolution', ...
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
        solution.profit_opt = [];
        solution.objective_value = [];
        solution.solver_name = 'linprog';
        return;
    end

    %% 6. Extract decision variables
    Pch  = x(model.idx.Pch);
    Pdis = x(model.idx.Pdis);
    SOC  = x(model.idx.SOC);

    if numel(Pch) ~= N || numel(Pdis) ~= N || numel(SOC) ~= N
        error('solve_caseB_lp:SolutionDimensionMismatch', ...
            'Extracted solution dimensions do not match data.N.');
    end

    %% 7. Recover optimisation quantities
    % linprog minimises f' * x = -profit
    profit_opt = -fval;

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
    solution.profit_opt = profit_opt;
    solution.objective_value = fval;
    solution.solver_name = 'linprog';

    %% 9. Additional diagnostics
    solution.charge_hours = sum(Pch > 1e-8);
    solution.discharge_hours = sum(Pdis > 1e-8);
    solution.idle_hours = sum((Pch <= 1e-8) & (Pdis <= 1e-8));
    solution.simultaneous_charge_discharge_hours = sum((Pch > 1e-8) & (Pdis > 1e-8));

    %% 10. Print summary
    fprintf('\n--- LP solve summary ---\n');
    fprintf('Exit flag                    : %d\n', exitflag);

    if isfield(output, 'message')
        fprintf('Solver message               : %s\n', strtrim(output.message));
    end

    fprintf('Objective value (min form)   : %.6f\n', fval);
    fprintf('Recovered profit (max form)  : %.6f GBP\n', profit_opt);
    fprintf('Charge-active hours          : %d\n', solution.charge_hours);
    fprintf('Discharge-active hours       : %d\n', solution.discharge_hours);
    fprintf('Idle hours                   : %d\n', solution.idle_hours);
    fprintf('Simultaneous ch/dis hours    : %d\n', ...
        solution.simultaneous_charge_discharge_hours);

    fprintf('Initial SOC from solution    : %.6f kWh\n', SOC(1));
    fprintf('Final SOC from solution      : %.6f kWh\n', SOC(end));
    fprintf('Terminal mode                : %s\n', params.terminalMode);

    if exitflag <= 0
        warning('solve_caseB_lp:NonOptimalExit', ...
            ['linprog did not report a standard successful optimal solve. ', ...
             'Check output.message for details.']);
    end

    fprintf('------------------------\n\n');
end