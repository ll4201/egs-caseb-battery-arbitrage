function verification = verify_caseB(data, params, solution, kpi)
% verify_caseB
% Verification checks for Case B:
% grid-scale battery arbitrage in the day-ahead market.
%
% INPUTS:
%   data        - struct returned by read_caseB_data
%   params      - parameter struct from main_caseB
%   solution    - struct returned by solve_caseB_lp
%   kpi         - struct returned by compute_kpis
%
% OUTPUT:
%   verification - struct containing verification metrics and flags
%
% Main checks included:
%   1) Unit consistency check
%   2) SOC dynamic equation residual
%   3) SOC lower/upper bound violations
%   4) Charge/discharge power bound violations
%   5) Initial SOC and terminal SOC checks
%   6) Profit recomputation consistency
%   7) Simultaneous charge/discharge detection
%   8) Time-step consistency check
%
% Notes:
% - This function is designed to support both report writing and debugging.
% - Small numerical residuals may occur due to solver tolerances.

    %% 1. Basic input checks
    requiredDataFields = {'price_mwh', 'price_kwh', 'dt', 'N'};
    for i = 1:numel(requiredDataFields)
        if ~isfield(data, requiredDataFields{i})
            error('verify_caseB:MissingDataField', ...
                'Missing required field data.%s', requiredDataFields{i});
        end
    end

    requiredParamFields = {'Emax', 'Pch_max', 'Pdis_max', ...
                           'eta_ch', 'eta_dis', 'SOC_init', 'terminalMode'};
    for i = 1:numel(requiredParamFields)
        if ~isfield(params, requiredParamFields{i})
            error('verify_caseB:MissingParamField', ...
                'Missing required field params.%s', requiredParamFields{i});
        end
    end

    requiredSolutionFields = {'Pch', 'Pdis', 'SOC', 'profit_opt'};
    for i = 1:numel(requiredSolutionFields)
        if ~isfield(solution, requiredSolutionFields{i})
            error('verify_caseB:MissingSolutionField', ...
                'Missing required field solution.%s', requiredSolutionFields{i});
        end
    end

    requiredKpiFields = {'total_profit_gbp_recomputed'};
    for i = 1:numel(requiredKpiFields)
        if ~isfield(kpi, requiredKpiFields{i})
            error('verify_caseB:MissingKPIField', ...
                'Missing required field kpi.%s', requiredKpiFields{i});
        end
    end

    %% 2. Extract variables
    N = data.N;
    dt = data.dt;

    price_mwh = data.price_mwh(:);
    price_kwh = data.price_kwh(:);

    Pch  = solution.Pch(:);
    Pdis = solution.Pdis(:);
    SOC  = solution.SOC(:);

    if numel(Pch) ~= N || numel(Pdis) ~= N || numel(SOC) ~= N
        error('verify_caseB:DimensionMismatch', ...
            'Dimensions of solution vectors do not match data.N.');
    end

    %% 3. Numerical tolerances
    tolResidual = 1e-7;
    tolBound = 1e-7;
    tolLogic = 1e-8;
    tolUnit = 1e-12;

    %% 4. Unit consistency check
    % Required by the coursework:
    % GBP/MWh -> GBP/kWh by dividing by 1000
    %
    % We verify that:
    %   price_kwh ?= price_mwh / 1000
    %
    % Also conceptually:
    %   GBP/kWh * kW * h = GBP
    unit_conversion_residual = price_kwh - price_mwh / 1000;
    max_unit_conversion_residual = max(abs(unit_conversion_residual));

    unit_check_pass = max_unit_conversion_residual <= tolUnit;

    % Example dimensional statement for report writing
    verification.unit_example_statement = ...
        'GBP/MWh converted to GBP/kWh via division by 1000; GBP/kWh × kW × h = GBP.';

    %% 5. SOC dynamic residual check
    % Model equation:
    % SOC(t+1) = SOC(t) + eta_ch*Pch(t)*dt - (Pdis(t)*dt)/eta_dis
    %
    % Rearranged residual:
    % r(t) = SOC(t+1) - SOC(t) - eta_ch*Pch(t)*dt + (Pdis(t)*dt)/eta_dis
    soc_residual = zeros(N - 1, 1);
    for t = 1:(N - 1)
        soc_residual(t) = SOC(t + 1) ...
                        - SOC(t) ...
                        - params.eta_ch * Pch(t) * dt ...
                        + (Pdis(t) * dt) / params.eta_dis;
    end

    max_soc_residual = max(abs(soc_residual));
    mean_soc_residual = mean(abs(soc_residual));
    soc_dynamic_check_pass = max_soc_residual <= tolResidual;

    %% 6. SOC bound checks
    % SOC should satisfy:
    % 0 <= SOC <= Emax
    soc_lower_violation_vector = max(0, -SOC);
    soc_upper_violation_vector = max(0, SOC - params.Emax);

    max_soc_lower_violation = max(soc_lower_violation_vector);
    max_soc_upper_violation = max(soc_upper_violation_vector);

    soc_bound_check_pass = (max_soc_lower_violation <= tolBound) && ...
                           (max_soc_upper_violation <= tolBound);

    %% 7. Charge/discharge power bound checks
    % 0 <= Pch <= Pch_max
    % 0 <= Pdis <= Pdis_max
    pch_lower_violation_vector = max(0, -Pch);
    pch_upper_violation_vector = max(0, Pch - params.Pch_max);

    pdis_lower_violation_vector = max(0, -Pdis);
    pdis_upper_violation_vector = max(0, Pdis - params.Pdis_max);

    max_pch_lower_violation = max(pch_lower_violation_vector);
    max_pch_violation = max(pch_upper_violation_vector);

    max_pdis_lower_violation = max(pdis_lower_violation_vector);
    max_pdis_violation = max(pdis_upper_violation_vector);

    power_bound_check_pass = (max_pch_lower_violation <= tolBound) && ...
                             (max_pch_violation <= tolBound) && ...
                             (max_pdis_lower_violation <= tolBound) && ...
                             (max_pdis_violation <= tolBound);

    %% 8. Initial and terminal SOC checks
    initial_soc_error = SOC(1) - params.SOC_init;
    max_initial_soc_error = abs(initial_soc_error);

    initial_soc_check_pass = max_initial_soc_error <= tolResidual;

    final_soc_error = SOC(end) - params.SOC_init;

    switch lower(params.terminalMode)
        case 'equal'
            terminal_soc_check_pass = abs(final_soc_error) <= tolResidual;
            terminal_constraint_type = 'SOC_final == SOC_init';
        case 'greater_equal'
            terminal_soc_check_pass = (SOC(end) + tolResidual) >= params.SOC_init;
            terminal_constraint_type = 'SOC_final >= SOC_init';
        otherwise
            error('verify_caseB:InvalidTerminalMode', ...
                'params.terminalMode must be ''equal'' or ''greater_equal''.');
    end

    %% 9. Profit recomputation consistency
    % Recompute profit independently:
    % profit = sum_t price_kwh(t) * (Pdis(t)-Pch(t)) * dt
    recomputed_profit_gbp = sum(price_kwh .* (Pdis - Pch) * dt);

    profit_difference = recomputed_profit_gbp - solution.profit_opt;
    max_profit_difference = abs(profit_difference);

    profit_check_pass = max_profit_difference <= 1e-6;

    %% 10. Simultaneous charge/discharge check
    simultaneous_mask = (Pch > tolLogic) & (Pdis > tolLogic);
    simultaneous_charge_discharge_hours = sum(simultaneous_mask);

    simultaneous_charge_discharge_energy_kwh = ...
        sum(min(Pch(simultaneous_mask), Pdis(simultaneous_mask)) * dt);

    % This is not a strict feasibility violation in this LP,
    % but it is still worth reporting.
    simultaneous_operation_present = simultaneous_charge_discharge_hours > 0;

    %% 11. Time-step consistency check
    time_step_check_available = false;
    time_step_max_deviation = NaN;
    time_step_check_pass = true;

    if isfield(data, 'timeStepHoursVector') && ~isempty(data.timeStepHoursVector)
        dtVec = data.timeStepHoursVector(:);
        time_step_check_available = true;
        time_step_max_deviation = max(abs(dtVec - dt));
        time_step_check_pass = time_step_max_deviation <= 1e-9;
    end

    %% 12. Price activity sanity check
    % A useful engineering sanity check:
    % average discharge price should typically exceed average charge price.
    charge_mask = Pch > tolLogic;
    discharge_mask = Pdis > tolLogic;

    if any(charge_mask)
        avg_charge_price_gbp_per_kwh = mean(price_kwh(charge_mask));
    else
        avg_charge_price_gbp_per_kwh = NaN;
    end

    if any(discharge_mask)
        avg_discharge_price_gbp_per_kwh = mean(price_kwh(discharge_mask));
    else
        avg_discharge_price_gbp_per_kwh = NaN;
    end

    economic_sanity_check_pass = true;
    if ~isnan(avg_charge_price_gbp_per_kwh) && ~isnan(avg_discharge_price_gbp_per_kwh)
        economic_sanity_check_pass = avg_discharge_price_gbp_per_kwh >= avg_charge_price_gbp_per_kwh;
    end

    %% 13. Overall verification status
    all_core_checks_pass = unit_check_pass && ...
                           soc_dynamic_check_pass && ...
                           soc_bound_check_pass && ...
                           power_bound_check_pass && ...
                           initial_soc_check_pass && ...
                           terminal_soc_check_pass && ...
                           profit_check_pass;

    %% 14. Pack outputs
    verification = struct();

    % Unit conversion
    verification.max_unit_conversion_residual = max_unit_conversion_residual;
    verification.unit_check_pass = unit_check_pass;

    % SOC dynamics
    verification.soc_residual = soc_residual;
    verification.max_soc_residual = max_soc_residual;
    verification.mean_soc_residual = mean_soc_residual;
    verification.soc_dynamic_check_pass = soc_dynamic_check_pass;

    % SOC bounds
    verification.soc_lower_violation_vector = soc_lower_violation_vector;
    verification.soc_upper_violation_vector = soc_upper_violation_vector;
    verification.max_soc_lower_violation = max_soc_lower_violation;
    verification.max_soc_upper_violation = max_soc_upper_violation;
    verification.soc_bound_check_pass = soc_bound_check_pass;

    % Power bounds
    verification.pch_lower_violation_vector = pch_lower_violation_vector;
    verification.pch_upper_violation_vector = pch_upper_violation_vector;
    verification.pdis_lower_violation_vector = pdis_lower_violation_vector;
    verification.pdis_upper_violation_vector = pdis_upper_violation_vector;

    verification.max_pch_lower_violation = max_pch_lower_violation;
    verification.max_pch_violation = max_pch_violation;
    verification.max_pdis_lower_violation = max_pdis_lower_violation;
    verification.max_pdis_violation = max_pdis_violation;
    verification.power_bound_check_pass = power_bound_check_pass;

    % Initial / terminal SOC
    verification.initial_soc_error = initial_soc_error;
    verification.max_initial_soc_error = max_initial_soc_error;
    verification.initial_soc_check_pass = initial_soc_check_pass;

    verification.final_soc_error = final_soc_error;
    verification.terminal_constraint_type = terminal_constraint_type;
    verification.terminal_soc_check_pass = terminal_soc_check_pass;

    % Profit consistency
    verification.recomputed_profit_gbp = recomputed_profit_gbp;
    verification.profit_difference = profit_difference;
    verification.max_profit_difference = max_profit_difference;
    verification.profit_check_pass = profit_check_pass;

    % Simultaneous charge / discharge
    verification.simultaneous_mask = simultaneous_mask;
    verification.simultaneous_charge_discharge_hours = simultaneous_charge_discharge_hours;
    verification.simultaneous_charge_discharge_energy_kwh = simultaneous_charge_discharge_energy_kwh;
    verification.simultaneous_operation_present = simultaneous_operation_present;

    % Time-step consistency
    verification.time_step_check_available = time_step_check_available;
    verification.time_step_max_deviation = time_step_max_deviation;
    verification.time_step_check_pass = time_step_check_pass;

    % Economic sanity
    verification.avg_charge_price_gbp_per_kwh = avg_charge_price_gbp_per_kwh;
    verification.avg_discharge_price_gbp_per_kwh = avg_discharge_price_gbp_per_kwh;
    verification.economic_sanity_check_pass = economic_sanity_check_pass;

    % Overall
    verification.all_core_checks_pass = all_core_checks_pass;
    verification.tolerances = struct( ...
        'tolResidual', tolResidual, ...
        'tolBound', tolBound, ...
        'tolLogic', tolLogic, ...
        'tolUnit', tolUnit);

    %% 15. Print summary
    fprintf('\n--- Verification summary ---\n');

    fprintf('Unit conversion residual       : %.6e\n', verification.max_unit_conversion_residual);
    fprintf('Unit conversion pass           : %d\n', verification.unit_check_pass);

    fprintf('Max SOC dynamic residual       : %.6e\n', verification.max_soc_residual);
    fprintf('Mean SOC dynamic residual      : %.6e\n', verification.mean_soc_residual);
    fprintf('SOC dynamics pass              : %d\n', verification.soc_dynamic_check_pass);

    fprintf('Max SOC lower violation        : %.6e\n', verification.max_soc_lower_violation);
    fprintf('Max SOC upper violation        : %.6e\n', verification.max_soc_upper_violation);
    fprintf('SOC bound pass                 : %d\n', verification.soc_bound_check_pass);

    fprintf('Max Pch lower violation        : %.6e\n', verification.max_pch_lower_violation);
    fprintf('Max Pch upper violation        : %.6e\n', verification.max_pch_violation);
    fprintf('Max Pdis lower violation       : %.6e\n', verification.max_pdis_lower_violation);
    fprintf('Max Pdis upper violation       : %.6e\n', verification.max_pdis_violation);
    fprintf('Power bound pass               : %d\n', verification.power_bound_check_pass);

    fprintf('Initial SOC error              : %.6e\n', verification.max_initial_soc_error);
    fprintf('Initial SOC pass               : %d\n', verification.initial_soc_check_pass);

    fprintf('Terminal SOC condition         : %s\n', verification.terminal_constraint_type);
    fprintf('Final SOC error vs init        : %.6e\n', verification.final_soc_error);
    fprintf('Terminal SOC pass              : %d\n', verification.terminal_soc_check_pass);

    fprintf('Profit recomputation diff      : %.6e GBP\n', verification.profit_difference);
    fprintf('Profit consistency pass        : %d\n', verification.profit_check_pass);

    fprintf('Simultaneous ch/dis hours      : %d\n', ...
        verification.simultaneous_charge_discharge_hours);
    fprintf('Simultaneous ch/dis energy     : %.6f kWh\n', ...
        verification.simultaneous_charge_discharge_energy_kwh);

    if verification.time_step_check_available
        fprintf('Time-step max deviation        : %.6e h\n', ...
            verification.time_step_max_deviation);
        fprintf('Time-step consistency pass     : %d\n', ...
            verification.time_step_check_pass);
    else
        fprintf('Time-step consistency pass     : N/A\n');
    end

    if ~isnan(verification.avg_charge_price_gbp_per_kwh)
        fprintf('Avg charge price              : %.6f GBP/kWh\n', ...
            verification.avg_charge_price_gbp_per_kwh);
    else
        fprintf('Avg charge price              : N/A\n');
    end

    if ~isnan(verification.avg_discharge_price_gbp_per_kwh)
        fprintf('Avg discharge price           : %.6f GBP/kWh\n', ...
            verification.avg_discharge_price_gbp_per_kwh);
    else
        fprintf('Avg discharge price           : N/A\n');
    end

    fprintf('Economic sanity pass           : %d\n', verification.economic_sanity_check_pass);
    fprintf('All core checks pass           : %d\n', verification.all_core_checks_pass);
    fprintf('-----------------------------\n\n');
end