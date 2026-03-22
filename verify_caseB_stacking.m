function verification = verify_caseB_stacking(data, params, solution, kpi)
% verify_caseB_stacking
% Verification checks for Case B extension:
% energy arbitrage + ancillary market stacking.
%
% INPUTS:
%   data        - struct returned by read_caseB_data
%   params      - parameter struct from main script
%   solution    - struct returned by solve_caseB_stacking_lp
%   kpi         - struct returned by compute_kpis_caseB_stacking
%
% OUTPUT:
%   verification - struct containing verification metrics and flags
%
% Main checks included:
%   1) Unit consistency checks
%   2) SOC dynamic equation residual
%   3) SOC lower/upper bound violations
%   4) Charge/discharge power bound violations
%   5) Reserve lower/upper bound violations
%   6) Charge-reserve sharing constraint checks
%   7) Discharge-reserve sharing constraint checks
%   8) Initial SOC and terminal SOC checks
%   9) Arbitrage revenue recomputation consistency
%   10) Ancillary revenue recomputation consistency
%   11) Total revenue consistency
%   12) Simultaneous charge/discharge detection
%   13) Time-step consistency check
%   14) Economic sanity checks
%
% Notes:
% - Small numerical residuals may occur due to solver tolerances.
% - This function is intended to support both report writing and debugging.

    %% 1. Basic input checks
    requiredDataFields = {'price_mwh', 'price_kwh', 'ancillary_price_mw_h', 'dt', 'N'};
    for i = 1:numel(requiredDataFields)
        if ~isfield(data, requiredDataFields{i})
            error('verify_caseB_stacking:MissingDataField', ...
                'Missing required field data.%s', requiredDataFields{i});
        end
    end

    requiredParamFields = {'Emax', 'Pch_max', 'Pdis_max', ...
                           'eta_ch', 'eta_dis', 'SOC_init', 'terminalMode'};
    for i = 1:numel(requiredParamFields)
        if ~isfield(params, requiredParamFields{i})
            error('verify_caseB_stacking:MissingParamField', ...
                'Missing required field params.%s', requiredParamFields{i});
        end
    end

    requiredSolutionFields = {'Pch', 'Pdis', 'SOC', 'R', ...
                              'arbitrage_revenue_gbp', ...
                              'ancillary_revenue_gbp', ...
                              'total_revenue_gbp'};
    for i = 1:numel(requiredSolutionFields)
        if ~isfield(solution, requiredSolutionFields{i})
            error('verify_caseB_stacking:MissingSolutionField', ...
                'Missing required field solution.%s', requiredSolutionFields{i});
        end
    end

    requiredKpiFields = {'total_revenue_gbp_recomputed', ...
                         'arbitrage_revenue_gbp_recomputed', ...
                         'ancillary_revenue_gbp_recomputed'};
    for i = 1:numel(requiredKpiFields)
        if ~isfield(kpi, requiredKpiFields{i})
            error('verify_caseB_stacking:MissingKPIField', ...
                'Missing required field kpi.%s', requiredKpiFields{i});
        end
    end

    %% 2. Extract variables
    N = data.N;
    dt = data.dt;

    price_mwh = data.price_mwh(:);               % GBP/MWh
    price_kwh = data.price_kwh(:);               % GBP/kWh
    price_anc = data.ancillary_price_mw_h(:);    % GBP/MW/h

    Pch  = solution.Pch(:);
    Pdis = solution.Pdis(:);
    SOC  = solution.SOC(:);
    R    = solution.R(:);

    if numel(Pch) ~= N || numel(Pdis) ~= N || numel(SOC) ~= N || numel(R) ~= N
        error('verify_caseB_stacking:DimensionMismatch', ...
            'Dimensions of solution vectors do not match data.N.');
    end

    %% 3. Numerical tolerances
    tolResidual = 1e-7;
    tolBound = 1e-7;
    tolLogic = 1e-8;
    tolUnit = 1e-12;
    tolRevenue = 1e-6;

    %% 4. Reserve upper bound
    if isfield(params, 'R_max') && ~isempty(params.R_max)
        R_max = params.R_max;
    else
        R_max = min(params.Pch_max, params.Pdis_max);
    end

    %% 5. Unit consistency checks
    % Check 1: GBP/MWh -> GBP/kWh conversion
    unit_conversion_residual_DA = price_kwh - price_mwh / 1000;
    max_unit_conversion_residual_DA = max(abs(unit_conversion_residual_DA));
    unit_check_DA_pass = max_unit_conversion_residual_DA <= tolUnit;

    % Check 2: ancillary term dimensional note
    % price_anc [GBP/MW/h] * (R/1000) [MW] * dt [h] = GBP
    ancillary_unit_statement = ...
        'GBP/MW/h × MW × h = GBP, using R(kW)/1000 = MW.';

    verification_unit_statement = ...
        ['Day-ahead price converted via GBP/MWh to GBP/kWh by division by 1000; ', ...
         ancillary_unit_statement];

    %% 6. SOC dynamic residual check
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

    %% 7. SOC bound checks
    soc_lower_violation_vector = max(0, -SOC);
    soc_upper_violation_vector = max(0, SOC - params.Emax);

    max_soc_lower_violation = max(soc_lower_violation_vector);
    max_soc_upper_violation = max(soc_upper_violation_vector);

    soc_bound_check_pass = (max_soc_lower_violation <= tolBound) && ...
                           (max_soc_upper_violation <= tolBound);

    %% 8. Charge/discharge power bound checks
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

    %% 9. Reserve bound checks
    r_lower_violation_vector = max(0, -R);
    r_upper_violation_vector = max(0, R - R_max);

    max_r_lower_violation = max(r_lower_violation_vector);
    max_r_upper_violation = max(r_upper_violation_vector);

    reserve_bound_check_pass = (max_r_lower_violation <= tolBound) && ...
                               (max_r_upper_violation <= tolBound);

    %% 10. Charge-reserve sharing constraint checks
    % Pch + R <= Pch_max
    charge_reserve_lhs = Pch + R;
    charge_reserve_violation_vector = max(0, charge_reserve_lhs - params.Pch_max);
    max_charge_reserve_violation = max(charge_reserve_violation_vector);
    charge_reserve_check_pass = max_charge_reserve_violation <= tolBound;

    %% 11. Discharge-reserve sharing constraint checks
    % Pdis + R <= Pdis_max
    discharge_reserve_lhs = Pdis + R;
    discharge_reserve_violation_vector = max(0, discharge_reserve_lhs - params.Pdis_max);
    max_discharge_reserve_violation = max(discharge_reserve_violation_vector);
    discharge_reserve_check_pass = max_discharge_reserve_violation <= tolBound;

    %% 12. Initial and terminal SOC checks
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
            error('verify_caseB_stacking:InvalidTerminalMode', ...
                'params.terminalMode must be ''equal'' or ''greater_equal''.');
    end

    %% 13. Revenue recomputation consistency
    % Arbitrage revenue
    recomputed_arbitrage_revenue_gbp = sum(price_kwh .* (Pdis - Pch) * dt);
    arbitrage_revenue_difference = recomputed_arbitrage_revenue_gbp - solution.arbitrage_revenue_gbp;
    max_arbitrage_revenue_difference = abs(arbitrage_revenue_difference);
    arbitrage_revenue_check_pass = max_arbitrage_revenue_difference <= tolRevenue;

    % Ancillary revenue
    recomputed_ancillary_revenue_gbp = sum(price_anc .* (R / 1000) * dt);
    ancillary_revenue_difference = recomputed_ancillary_revenue_gbp - solution.ancillary_revenue_gbp;
    max_ancillary_revenue_difference = abs(ancillary_revenue_difference);
    ancillary_revenue_check_pass = max_ancillary_revenue_difference <= tolRevenue;

    % Total revenue
    recomputed_total_revenue_gbp = ...
        recomputed_arbitrage_revenue_gbp + recomputed_ancillary_revenue_gbp;
    total_revenue_difference = recomputed_total_revenue_gbp - solution.total_revenue_gbp;
    max_total_revenue_difference = abs(total_revenue_difference);
    total_revenue_check_pass = max_total_revenue_difference <= tolRevenue;

    % Cross-check against fval-derived total revenue if available
    if isfield(solution, 'recovered_total_revenue_from_fval') && ~isempty(solution.recovered_total_revenue_from_fval)
        recovered_total_revenue_difference = ...
            recomputed_total_revenue_gbp - solution.recovered_total_revenue_from_fval;
        max_recovered_total_revenue_difference = abs(recovered_total_revenue_difference);
    else
        recovered_total_revenue_difference = NaN;
        max_recovered_total_revenue_difference = NaN;
    end

    %% 14. Simultaneous operation checks
    simultaneous_charge_discharge_mask = (Pch > tolLogic) & (Pdis > tolLogic);
    simultaneous_charge_reserve_mask = (Pch > tolLogic) & (R > tolLogic);
    simultaneous_discharge_reserve_mask = (Pdis > tolLogic) & (R > tolLogic);

    simultaneous_charge_discharge_hours = sum(simultaneous_charge_discharge_mask);
    simultaneous_charge_reserve_hours = sum(simultaneous_charge_reserve_mask);
    simultaneous_discharge_reserve_hours = sum(simultaneous_discharge_reserve_mask);

    simultaneous_charge_discharge_energy_kwh = ...
        sum(min(Pch(simultaneous_charge_discharge_mask), ...
                Pdis(simultaneous_charge_discharge_mask)) * dt);

    simultaneous_operation_present = ...
        (simultaneous_charge_discharge_hours > 0);

    %% 15. Time-step consistency check
    time_step_check_available = false;
    time_step_max_deviation = NaN;
    time_step_check_pass = true;

    if isfield(data, 'timeStepHoursVector') && ~isempty(data.timeStepHoursVector)
        dtVec = data.timeStepHoursVector(:);
        time_step_check_available = true;
        time_step_max_deviation = max(abs(dtVec - dt));
        time_step_check_pass = time_step_max_deviation <= 1e-9;
    end

    %% 16. Economic sanity checks
    charge_mask = Pch > tolLogic;
    discharge_mask = Pdis > tolLogic;
    reserve_mask = R > tolLogic;

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

    if any(reserve_mask)
        avg_ancillary_price_when_reserved_gbp_per_mw_h = mean(price_anc(reserve_mask));
    else
        avg_ancillary_price_when_reserved_gbp_per_mw_h = NaN;
    end

    economic_sanity_arbitrage_pass = true;
    if ~isnan(avg_charge_price_gbp_per_kwh) && ~isnan(avg_discharge_price_gbp_per_kwh)
        economic_sanity_arbitrage_pass = ...
            avg_discharge_price_gbp_per_kwh >= avg_charge_price_gbp_per_kwh;
    end

    economic_sanity_ancillary_pass = true;
    if ~isnan(avg_ancillary_price_when_reserved_gbp_per_mw_h)
        economic_sanity_ancillary_pass = avg_ancillary_price_when_reserved_gbp_per_mw_h >= 0;
    end

    %% 17. Overall verification status
    all_core_checks_pass = unit_check_DA_pass && ...
                           soc_dynamic_check_pass && ...
                           soc_bound_check_pass && ...
                           power_bound_check_pass && ...
                           reserve_bound_check_pass && ...
                           charge_reserve_check_pass && ...
                           discharge_reserve_check_pass && ...
                           initial_soc_check_pass && ...
                           terminal_soc_check_pass && ...
                           arbitrage_revenue_check_pass && ...
                           ancillary_revenue_check_pass && ...
                           total_revenue_check_pass;

    %% 18. Pack outputs
    verification = struct();

    % Unit checks
    verification.max_unit_conversion_residual_DA = max_unit_conversion_residual_DA;
    verification.unit_check_DA_pass = unit_check_DA_pass;
    verification.unit_statement = verification_unit_statement;

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

    % Reserve bounds
    verification.r_lower_violation_vector = r_lower_violation_vector;
    verification.r_upper_violation_vector = r_upper_violation_vector;
    verification.max_r_lower_violation = max_r_lower_violation;
    verification.max_r_upper_violation = max_r_upper_violation;
    verification.reserve_bound_check_pass = reserve_bound_check_pass;
    verification.R_max = R_max;

    % Charge-reserve sharing
    verification.charge_reserve_lhs = charge_reserve_lhs;
    verification.charge_reserve_violation_vector = charge_reserve_violation_vector;
    verification.max_charge_reserve_violation = max_charge_reserve_violation;
    verification.charge_reserve_check_pass = charge_reserve_check_pass;

    % Discharge-reserve sharing
    verification.discharge_reserve_lhs = discharge_reserve_lhs;
    verification.discharge_reserve_violation_vector = discharge_reserve_violation_vector;
    verification.max_discharge_reserve_violation = max_discharge_reserve_violation;
    verification.discharge_reserve_check_pass = discharge_reserve_check_pass;

    % Initial / terminal SOC
    verification.initial_soc_error = initial_soc_error;
    verification.max_initial_soc_error = max_initial_soc_error;
    verification.initial_soc_check_pass = initial_soc_check_pass;

    verification.final_soc_error = final_soc_error;
    verification.terminal_constraint_type = terminal_constraint_type;
    verification.terminal_soc_check_pass = terminal_soc_check_pass;

    % Revenue consistency
    verification.recomputed_arbitrage_revenue_gbp = recomputed_arbitrage_revenue_gbp;
    verification.arbitrage_revenue_difference = arbitrage_revenue_difference;
    verification.max_arbitrage_revenue_difference = max_arbitrage_revenue_difference;
    verification.arbitrage_revenue_check_pass = arbitrage_revenue_check_pass;

    verification.recomputed_ancillary_revenue_gbp = recomputed_ancillary_revenue_gbp;
    verification.ancillary_revenue_difference = ancillary_revenue_difference;
    verification.max_ancillary_revenue_difference = max_ancillary_revenue_difference;
    verification.ancillary_revenue_check_pass = ancillary_revenue_check_pass;

    verification.recomputed_total_revenue_gbp = recomputed_total_revenue_gbp;
    verification.total_revenue_difference = total_revenue_difference;
    verification.max_total_revenue_difference = max_total_revenue_difference;
    verification.total_revenue_check_pass = total_revenue_check_pass;

    verification.recovered_total_revenue_difference = recovered_total_revenue_difference;
    verification.max_recovered_total_revenue_difference = max_recovered_total_revenue_difference;

    % Simultaneous operations
    verification.simultaneous_charge_discharge_mask = simultaneous_charge_discharge_mask;
    verification.simultaneous_charge_reserve_mask = simultaneous_charge_reserve_mask;
    verification.simultaneous_discharge_reserve_mask = simultaneous_discharge_reserve_mask;

    verification.simultaneous_charge_discharge_hours = simultaneous_charge_discharge_hours;
    verification.simultaneous_charge_reserve_hours = simultaneous_charge_reserve_hours;
    verification.simultaneous_discharge_reserve_hours = simultaneous_discharge_reserve_hours;
    verification.simultaneous_charge_discharge_energy_kwh = simultaneous_charge_discharge_energy_kwh;
    verification.simultaneous_operation_present = simultaneous_operation_present;

    % Time-step consistency
    verification.time_step_check_available = time_step_check_available;
    verification.time_step_max_deviation = time_step_max_deviation;
    verification.time_step_check_pass = time_step_check_pass;

    % Economic sanity
    verification.avg_charge_price_gbp_per_kwh = avg_charge_price_gbp_per_kwh;
    verification.avg_discharge_price_gbp_per_kwh = avg_discharge_price_gbp_per_kwh;
    verification.avg_ancillary_price_when_reserved_gbp_per_mw_h = ...
        avg_ancillary_price_when_reserved_gbp_per_mw_h;
    verification.economic_sanity_arbitrage_pass = economic_sanity_arbitrage_pass;
    verification.economic_sanity_ancillary_pass = economic_sanity_ancillary_pass;

    % Overall
    verification.all_core_checks_pass = all_core_checks_pass;
    verification.tolerances = struct( ...
        'tolResidual', tolResidual, ...
        'tolBound', tolBound, ...
        'tolLogic', tolLogic, ...
        'tolUnit', tolUnit, ...
        'tolRevenue', tolRevenue);

    %% 19. Print summary
    fprintf('\n--- Stacking verification summary ---\n');

    fprintf('Max DA unit conversion residual       : %.6e\n', ...
        verification.max_unit_conversion_residual_DA);
    fprintf('DA unit conversion pass               : %d\n', ...
        verification.unit_check_DA_pass);

    fprintf('Max SOC dynamic residual              : %.6e\n', ...
        verification.max_soc_residual);
    fprintf('Mean SOC dynamic residual             : %.6e\n', ...
        verification.mean_soc_residual);
    fprintf('SOC dynamics pass                     : %d\n', ...
        verification.soc_dynamic_check_pass);

    fprintf('Max SOC lower violation               : %.6e\n', ...
        verification.max_soc_lower_violation);
    fprintf('Max SOC upper violation               : %.6e\n', ...
        verification.max_soc_upper_violation);
    fprintf('SOC bound pass                        : %d\n', ...
        verification.soc_bound_check_pass);

    fprintf('Max Pch upper violation               : %.6e\n', ...
        verification.max_pch_violation);
    fprintf('Max Pdis upper violation              : %.6e\n', ...
        verification.max_pdis_violation);
    fprintf('Power bound pass                      : %d\n', ...
        verification.power_bound_check_pass);

    fprintf('Max reserve lower violation           : %.6e\n', ...
        verification.max_r_lower_violation);
    fprintf('Max reserve upper violation           : %.6e\n', ...
        verification.max_r_upper_violation);
    fprintf('Reserve bound pass                    : %d\n', ...
        verification.reserve_bound_check_pass);

    fprintf('Max charge-reserve violation          : %.6e\n', ...
        verification.max_charge_reserve_violation);
    fprintf('Charge-reserve pass                   : %d\n', ...
        verification.charge_reserve_check_pass);

    fprintf('Max discharge-reserve violation       : %.6e\n', ...
        verification.max_discharge_reserve_violation);
    fprintf('Discharge-reserve pass                : %d\n', ...
        verification.discharge_reserve_check_pass);

    fprintf('Initial SOC error                     : %.6e\n', ...
        verification.max_initial_soc_error);
    fprintf('Initial SOC pass                      : %d\n', ...
        verification.initial_soc_check_pass);

    fprintf('Terminal SOC condition                : %s\n', ...
        verification.terminal_constraint_type);
    fprintf('Final SOC error vs init               : %.6e\n', ...
        verification.final_soc_error);
    fprintf('Terminal SOC pass                     : %d\n', ...
        verification.terminal_soc_check_pass);

    fprintf('Arbitrage revenue diff                : %.6e GBP\n', ...
        verification.arbitrage_revenue_difference);
    fprintf('Arbitrage revenue pass                : %d\n', ...
        verification.arbitrage_revenue_check_pass);

    fprintf('Ancillary revenue diff                : %.6e GBP\n', ...
        verification.ancillary_revenue_difference);
    fprintf('Ancillary revenue pass                : %d\n', ...
        verification.ancillary_revenue_check_pass);

    fprintf('Total revenue diff                    : %.6e GBP\n', ...
        verification.total_revenue_difference);
    fprintf('Total revenue pass                    : %d\n', ...
        verification.total_revenue_check_pass);

    fprintf('Simultaneous ch/dis hours             : %d\n', ...
        verification.simultaneous_charge_discharge_hours);
    fprintf('Simultaneous ch/reserve hours         : %d\n', ...
        verification.simultaneous_charge_reserve_hours);
    fprintf('Simultaneous dis/reserve hours        : %d\n', ...
        verification.simultaneous_discharge_reserve_hours);

    if verification.time_step_check_available
        fprintf('Time-step max deviation               : %.6e h\n', ...
            verification.time_step_max_deviation);
        fprintf('Time-step consistency pass            : %d\n', ...
            verification.time_step_check_pass);
    else
        fprintf('Time-step consistency pass            : N/A\n');
    end

    if ~isnan(verification.avg_charge_price_gbp_per_kwh)
        fprintf('Avg charge price                      : %.6f GBP/kWh\n', ...
            verification.avg_charge_price_gbp_per_kwh);
    else
        fprintf('Avg charge price                      : N/A\n');
    end

    if ~isnan(verification.avg_discharge_price_gbp_per_kwh)
        fprintf('Avg discharge price                   : %.6f GBP/kWh\n', ...
            verification.avg_discharge_price_gbp_per_kwh);
    else
        fprintf('Avg discharge price                   : N/A\n');
    end

    if ~isnan(verification.avg_ancillary_price_when_reserved_gbp_per_mw_h)
        fprintf('Avg ancillary price when reserved     : %.6f GBP/MW/h\n', ...
            verification.avg_ancillary_price_when_reserved_gbp_per_mw_h);
    else
        fprintf('Avg ancillary price when reserved     : N/A\n');
    end

    fprintf('Economic sanity (arbitrage) pass      : %d\n', ...
        verification.economic_sanity_arbitrage_pass);
    fprintf('Economic sanity (ancillary) pass      : %d\n', ...
        verification.economic_sanity_ancillary_pass);
    fprintf('All core checks pass                  : %d\n', ...
        verification.all_core_checks_pass);

    fprintf('--------------------------------------\n\n');
end