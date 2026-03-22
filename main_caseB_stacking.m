%% main_caseB_stacking.m
% KCL Coursework - Case B Extension: Market Stacking
% Base energy arbitrage + ancillary market capacity reservation
%
% Author: [Your Name]
% Date: [Fill in date]
%
% This script performs:
% 1) Data loading and preprocessing
% 2) Battery and reserve parameter setup
% 3) Stacking LP model construction
% 4) LP solution using linprog
% 5) KPI calculation
% 6) Verification checks
% 7) Save workspace and key tables
%
% Notes:
% - Day-ahead price is used for arbitrage revenue.
% - Ancillary availability price is used for reserve capacity revenue.
% - Reserve is modelled as capacity reservation only (no activation energy).
% - Time step is assumed to be 1 hour unless checked otherwise in the data.

clear; clc; close all;

%% 0. User settings
dataFile = 'caseB_grid_battery_market_hourly.csv';   % or fullfile('data', ...)
resultsDir = 'results_stacking';

displaySummary = true;

if ~exist(resultsDir, 'dir')
    mkdir(resultsDir);
end

%% 1. Read and preprocess data
fprintf('Step 1/6: Reading input data...\n');

data = read_caseB_data(dataFile);

fprintf('Data loaded successfully.\n');
fprintf('Number of time steps: %d\n', data.N);
fprintf('Time step: %.3f h\n', data.dt);
fprintf('Day-ahead price range (GBP/MWh): [%.2f, %.2f]\n', ...
    min(data.price_mwh), max(data.price_mwh));

if isempty(data.ancillary_price_mw_h)
    error('main_caseB_stacking:MissingAncillaryColumn', ...
        'Ancillary price column is empty or not available in the imported dataset.');
end

fprintf('Ancillary price range (GBP/MW/h): [%.2f, %.2f]\n', ...
    min(data.ancillary_price_mw_h), max(data.ancillary_price_mw_h));

%% 2. Define battery and reserve parameters
fprintf('\nStep 2/6: Setting battery and reserve parameters...\n');

params = struct();

% Battery parameters from coursework brief
params.Emax      = 2000;      % kWh (2 MWh)
params.Pch_max   = 1000;      % kW  (1 MW)
params.Pdis_max  = 1000;      % kW  (1 MW)

% Round-trip efficiency = 88%
params.eta_ch    = sqrt(0.88);
params.eta_dis   = sqrt(0.88);

params.dt        = data.dt;   % h
params.N         = data.N;

% Initial SOC = 50% of capacity
params.SOC_init  = 0.5 * params.Emax;   % kWh

% Terminal SOC treatment
params.terminalMode = 'equal';   % 'equal' or 'greater_equal'

% Reserve upper bound (optional, default in builder is min(Pch_max,Pdis_max))
params.R_max = min(params.Pch_max, params.Pdis_max);

fprintf('Battery / reserve parameters set.\n');
fprintf('Emax        = %.1f kWh\n', params.Emax);
fprintf('Pch_max     = %.1f kW\n', params.Pch_max);
fprintf('Pdis_max    = %.1f kW\n', params.Pdis_max);
fprintf('R_max       = %.1f kW\n', params.R_max);
fprintf('eta_ch      = %.4f\n', params.eta_ch);
fprintf('eta_dis     = %.4f\n', params.eta_dis);
fprintf('SOC_init    = %.1f kWh\n', params.SOC_init);
fprintf('terminalMode= %s\n', params.terminalMode);

%% 3. Build stacking LP model
fprintf('\nStep 3/6: Building stacking LP model...\n');

model = build_caseB_stacking_lp(data, params);

fprintf('Stacking LP model built successfully.\n');
fprintf('Total decision variables: %d\n', length(model.f));

%% 4. Solve optimization problem
fprintf('\nStep 4/6: Solving stacking LP using linprog...\n');

solution = solve_caseB_stacking_lp(model, data, params);

if solution.exitflag <= 0
    warning('main_caseB_stacking:NonOptimalSolve', ...
        'Optimization may not have converged. Please check solver output.');
else
    fprintf('Optimization finished successfully.\n');
end

%% 5. Compute KPIs
fprintf('\nStep 5/6: Computing stacking KPIs...\n');

kpi = compute_kpis_caseB_stacking(data, params, solution);

fprintf('Stacking KPI calculation complete.\n');

%% 6. Verification checks
fprintf('\nStep 6/6: Running stacking verification checks...\n');

verification = verify_caseB_stacking(data, params, solution, kpi);

fprintf('Stacking verification complete.\n');

%% 7. Display summary
if displaySummary
    fprintf('\n================ STACKING SUMMARY ================\n');
    fprintf('Total stacked revenue              : %.4f GBP\n', kpi.total_revenue_gbp);
    fprintf('  Arbitrage revenue                : %.4f GBP\n', kpi.arbitrage_revenue_gbp);
    fprintf('  Ancillary revenue                : %.4f GBP\n', kpi.ancillary_revenue_gbp);
    fprintf('Ancillary revenue share            : %.4f\n', kpi.ancillary_revenue_share);

    fprintf('Total charge energy                : %.4f kWh\n', kpi.total_charge_kwh);
    fprintf('Total discharge energy             : %.4f kWh\n', kpi.total_discharge_kwh);
    fprintf('Energy throughput                  : %.4f kWh\n', kpi.energy_throughput_kwh);

    fprintf('SOC min / max                      : %.4f / %.4f kWh\n', ...
        kpi.soc_min_kwh, kpi.soc_max_kwh);
    fprintf('Initial SOC                        : %.4f kWh\n', ...
        kpi.soc_initial_kwh_from_solution);
    fprintf('Final SOC                          : %.4f kWh\n', ...
        kpi.soc_final_kwh);

    fprintf('Charge / discharge / reserve hrs   : %d / %d / %d\n', ...
        kpi.charge_hours, kpi.discharge_hours, kpi.reserve_active_hours);
    fprintf('Average reserved capacity          : %.4f kW\n', ...
        kpi.avg_reserved_capacity_kw);
    fprintf('Maximum reserved capacity          : %.4f kW\n', ...
        kpi.max_reserved_capacity_kw);

    fprintf('\nVerification results:\n');
    fprintf('Max SOC dynamic residual          : %.6e\n', verification.max_soc_residual);
    fprintf('Max SOC lower violation           : %.6e\n', verification.max_soc_lower_violation);
    fprintf('Max SOC upper violation           : %.6e\n', verification.max_soc_upper_violation);
    fprintf('Max Pch upper violation           : %.6e\n', verification.max_pch_violation);
    fprintf('Max Pdis upper violation          : %.6e\n', verification.max_pdis_violation);
    fprintf('Max reserve upper violation       : %.6e\n', verification.max_r_upper_violation);
    fprintf('Max charge-reserve violation      : %.6e\n', verification.max_charge_reserve_violation);
    fprintf('Max discharge-reserve violation   : %.6e\n', verification.max_discharge_reserve_violation);
    fprintf('Arbitrage revenue diff            : %.6e GBP\n', verification.arbitrage_revenue_difference);
    fprintf('Ancillary revenue diff            : %.6e GBP\n', verification.ancillary_revenue_difference);
    fprintf('Total revenue diff                : %.6e GBP\n', verification.total_revenue_difference);
    fprintf('All core checks pass              : %d\n', verification.all_core_checks_pass);
    fprintf('==================================================\n');
end

%% 8. Save numerical results
fprintf('\nSaving stacking results...\n');

save(fullfile(resultsDir, 'caseB_stacking_workspace.mat'), ...
    'data', 'params', 'model', 'solution', 'kpi', 'verification');

%% 9. Save compact KPI table
kpiTable = table( ...
    kpi.total_revenue_gbp, ...
    kpi.arbitrage_revenue_gbp, ...
    kpi.ancillary_revenue_gbp, ...
    kpi.ancillary_revenue_share, ...
    kpi.total_charge_kwh, ...
    kpi.total_discharge_kwh, ...
    kpi.energy_throughput_kwh, ...
    kpi.soc_min_kwh, ...
    kpi.soc_max_kwh, ...
    kpi.soc_final_kwh, ...
    kpi.avg_reserved_capacity_kw, ...
    kpi.max_reserved_capacity_kw, ...
    kpi.reserve_active_hours, ...
    'VariableNames', { ...
    'TotalRevenue_GBP', ...
    'ArbitrageRevenue_GBP', ...
    'AncillaryRevenue_GBP', ...
    'AncillaryRevenueShare', ...
    'TotalCharge_kWh', ...
    'TotalDischarge_kWh', ...
    'EnergyThroughput_kWh', ...
    'SOCmin_kWh', ...
    'SOCmax_kWh', ...
    'SOCfinal_kWh', ...
    'AvgReservedCapacity_kW', ...
    'MaxReservedCapacity_kW', ...
    'ReserveActiveHours'});

writetable(kpiTable, fullfile(resultsDir, 'caseB_stacking_kpis.csv'));

%% 10. Save verification table
verificationTable = table( ...
    verification.max_unit_conversion_residual_DA, ...
    verification.max_soc_residual, ...
    verification.max_soc_lower_violation, ...
    verification.max_soc_upper_violation, ...
    verification.max_pch_violation, ...
    verification.max_pdis_violation, ...
    verification.max_r_upper_violation, ...
    verification.max_charge_reserve_violation, ...
    verification.max_discharge_reserve_violation, ...
    verification.arbitrage_revenue_difference, ...
    verification.ancillary_revenue_difference, ...
    verification.total_revenue_difference, ...
    verification.all_core_checks_pass, ...
    'VariableNames', { ...
    'MaxDAUnitConversionResidual', ...
    'MaxSOCDynamicResidual', ...
    'MaxSOCLowerViolation', ...
    'MaxSOCUpperViolation', ...
    'MaxPchViolation', ...
    'MaxPdisViolation', ...
    'MaxReserveUpperViolation', ...
    'MaxChargeReserveViolation', ...
    'MaxDischargeReserveViolation', ...
    'ArbitrageRevenueDifference_GBP', ...
    'AncillaryRevenueDifference_GBP', ...
    'TotalRevenueDifference_GBP', ...
    'AllCoreChecksPass'});

writetable(verificationTable, fullfile(resultsDir, 'caseB_stacking_verification.csv'));

fprintf('\nAll stacking tasks completed.\n');
fprintf('Results saved in folder: %s\n', resultsDir);