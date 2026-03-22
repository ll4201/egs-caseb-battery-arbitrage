%% main_caseB.m
% KCL Coursework - Case B: Grid-Scale Battery in Electricity Markets
% Base case: day-ahead market arbitrage using linear programming
%
% Author: [Your Name]
% Date: [Fill in date]
%
% This script performs:
% 1) Data loading and preprocessing
% 2) Battery parameter setup
% 3) LP model construction
% 4) LP solution using linprog
% 5) KPI calculation
% 6) Verification checks
% 7) Plotting and result export
%
% Notes:
% - Base case uses only day-ahead price for arbitrage.
% - Prices in the CSV are assumed to be in GBP/MWh and converted to GBP/kWh.
% - Time step is assumed to be 1 hour unless checked otherwise in the data.

clear; clc; close all;

%% 0. User settings
dataFile = 'caseB_grid_battery_market_hourly.csv';   % CSV file name
resultsDir = 'results';                              % Folder to save outputs
figDir = fullfile(resultsDir, 'figures');

saveFigures = true;      % true = save plots
displaySummary = true;   % true = print summary in command window

% Create result folders if they do not exist
if ~exist(resultsDir, 'dir')
    mkdir(resultsDir);
end
if ~exist(figDir, 'dir')
    mkdir(figDir);
end

%% 1. Read and preprocess data
fprintf('Step 1/6: Reading input data...\n');

data = read_caseB_data(dataFile);

% Expected fields from read_caseB_data:
% data.time                 datetime vector
% data.price_mwh           day-ahead price in GBP/MWh
% data.price_kwh           day-ahead price in GBP/kWh
% data.N                   number of time steps
% data.dt                  time step in hours

fprintf('Data loaded successfully.\n');
fprintf('Number of time steps: %d\n', data.N);
fprintf('Time step: %.3f h\n', data.dt);
fprintf('Price range (GBP/MWh): [%.2f, %.2f]\n', min(data.price_mwh), max(data.price_mwh));

%% 2. Define battery parameters
fprintf('\nStep 2/6: Setting battery parameters...\n');

params = struct();

% Battery parameters from coursework brief
params.Emax      = 2000;      % kWh (2 MWh)
params.Pch_max   = 1000;      % kW  (1 MW)
params.Pdis_max  = 1000;      % kW  (1 MW)

% Round-trip efficiency = 88%
% Symmetric charge/discharge efficiency approximation
params.eta_ch    = sqrt(0.88);
params.eta_dis   = sqrt(0.88);

params.dt        = data.dt;   % h
params.N         = data.N;

% Initial state of charge: 50% of capacity
params.SOC_init  = 0.5 * params.Emax;   % kWh

% End-of-horizon SOC treatment
% Option 1: terminal SOC equals initial SOC
params.terminalMode = 'equal';   % 'equal' or 'greater_equal'

% Solver settings
params.useSimultaneousChargeDischargePenalty = false;
% For a pure LP base case, simultaneous charge/discharge is usually avoided
% by economics + efficiency losses, but can still happen in edge cases.
% We leave it false here for simplicity.

fprintf('Battery parameters set.\n');
fprintf('Emax     = %.1f kWh\n', params.Emax);
fprintf('Pch_max  = %.1f kW\n', params.Pch_max);
fprintf('Pdis_max = %.1f kW\n', params.Pdis_max);
fprintf('eta_ch   = %.4f\n', params.eta_ch);
fprintf('eta_dis  = %.4f\n', params.eta_dis);
fprintf('SOC_init = %.1f kWh\n', params.SOC_init);

%% 3. Build linear programming model
fprintf('\nStep 3/6: Building LP model...\n');

model = build_caseB_lp(data, params);

% Expected fields from build_caseB_lp:
% model.f, model.A, model.b, model.Aeq, model.beq, model.lb, model.ub
% model.idx.Pch, model.idx.Pdis, model.idx.SOC

fprintf('LP model built successfully.\n');
fprintf('Total decision variables: %d\n', length(model.f));

%% 4. Solve optimization problem
fprintf('\nStep 4/6: Solving LP using linprog...\n');

solution = solve_caseB_lp(model, data, params);

% Expected fields from solve_caseB_lp:
% solution.x
% solution.exitflag
% solution.output
% solution.fval
% solution.Pch
% solution.Pdis
% solution.SOC
% solution.profit_opt

if solution.exitflag <= 0
    warning('Optimization may not have converged. Please check solver output.');
else
    fprintf('Optimization finished successfully.\n');
end

%% 5. Compute KPIs
fprintf('\nStep 5/6: Computing KPIs...\n');

kpi = compute_kpis(data, params, solution);

% Expected KPI fields:
% kpi.total_profit_gbp
% kpi.total_charge_kwh
% kpi.total_discharge_kwh
% kpi.energy_throughput_kwh
% kpi.soc_min_kwh
% kpi.soc_max_kwh
% kpi.soc_final_kwh

fprintf('KPI calculation complete.\n');

%% 6. Verification checks
fprintf('\nStep 6/6: Running verification checks...\n');

verification = verify_caseB(data, params, solution, kpi);

fprintf('Verification complete.\n');

%% 7. Display summary
if displaySummary
    fprintf('\n================ CASE B SUMMARY ================\n');
    fprintf('Total profit              : %.4f GBP\n', kpi.total_profit_gbp);
    fprintf('Total charge energy       : %.4f kWh\n', kpi.total_charge_kwh);
    fprintf('Total discharge energy    : %.4f kWh\n', kpi.total_discharge_kwh);
    fprintf('Energy throughput         : %.4f kWh\n', kpi.energy_throughput_kwh);
    fprintf('SOC min / max             : %.4f / %.4f kWh\n', ...
        kpi.soc_min_kwh, kpi.soc_max_kwh);
    fprintf('Initial SOC               : %.4f kWh\n', params.SOC_init);
    fprintf('Final SOC                 : %.4f kWh\n', kpi.soc_final_kwh);
    fprintf('\nVerification results:\n');
    fprintf('Max SOC dynamic residual  : %.6e\n', verification.max_soc_residual);
    fprintf('Max SOC lower violation   : %.6e\n', verification.max_soc_lower_violation);
    fprintf('Max SOC upper violation   : %.6e\n', verification.max_soc_upper_violation);
    fprintf('Max Pch upper violation   : %.6e\n', verification.max_pch_violation);
    fprintf('Max Pdis upper violation  : %.6e\n', verification.max_pdis_violation);
    fprintf('Profit recomputation diff : %.6e GBP\n', verification.profit_difference);
    fprintf('================================================\n');
end

%% 8. Plot results
fprintf('\nGenerating plots...\n');

plot_caseB_results(data, params, solution, kpi, figDir, saveFigures);

%% 9. Save numerical results
fprintf('Saving results...\n');

save(fullfile(resultsDir, 'caseB_basecase_workspace.mat'), ...
    'data', 'params', 'model', 'solution', 'kpi', 'verification');

% Save a compact KPI table
kpiTable = table( ...
    kpi.total_profit_gbp, ...
    kpi.total_charge_kwh, ...
    kpi.total_discharge_kwh, ...
    kpi.energy_throughput_kwh, ...
    kpi.soc_min_kwh, ...
    kpi.soc_max_kwh, ...
    kpi.soc_final_kwh, ...
    'VariableNames', { ...
    'TotalProfit_GBP', ...
    'TotalCharge_kWh', ...
    'TotalDischarge_kWh', ...
    'EnergyThroughput_kWh', ...
    'SOCmin_kWh', ...
    'SOCmax_kWh', ...
    'SOCfinal_kWh'});

writetable(kpiTable, fullfile(resultsDir, 'caseB_basecase_kpis.csv'));

% Save verification table
verificationTable = table( ...
    verification.max_soc_residual, ...
    verification.max_soc_lower_violation, ...
    verification.max_soc_upper_violation, ...
    verification.max_pch_violation, ...
    verification.max_pdis_violation, ...
    verification.profit_difference, ...
    'VariableNames', { ...
    'MaxSOCDynamicResidual', ...
    'MaxSOCLowerViolation', ...
    'MaxSOCUpperViolation', ...
    'MaxPchViolation', ...
    'MaxPdisViolation', ...
    'ProfitDifference_GBP'});

writetable(verificationTable, fullfile(resultsDir, 'caseB_basecase_verification.csv'));

fprintf('\nAll tasks completed.\n');
fprintf('Results saved in folder: %s\n', resultsDir);