%% compare_caseB_base_vs_stacking.m
% Compare Case B base case vs market stacking extension
%
% This script:
% 1) Loads saved .mat workspaces for base case and stacking case
% 2) Extracts key KPIs
% 3) Builds comparison tables
% 4) Computes absolute and percentage changes
% 5) Saves tables to CSV for later report writing
%
% Expected input files:
%   results/caseB_basecase_workspace.mat
%   results_stacking/caseB_stacking_workspace.mat

clear; clc;

%% 0. User settings
baseMatFile = fullfile('results', 'caseB_basecase_workspace.mat');
stackMatFile = fullfile('results_stacking', 'caseB_stacking_workspace.mat');

outputDir = 'results_comparison';
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% 1. Load saved workspaces
fprintf('Loading base case workspace...\n');
if ~isfile(baseMatFile)
    error('compare_caseB_base_vs_stacking:BaseFileNotFound', ...
        'Base case workspace not found: %s', baseMatFile);
end
baseData = load(baseMatFile);

fprintf('Loading stacking case workspace...\n');
if ~isfile(stackMatFile)
    error('compare_caseB_base_vs_stacking:StackFileNotFound', ...
        'Stacking case workspace not found: %s', stackMatFile);
end
stackData = load(stackMatFile);

%% 2. Check required variables
requiredBaseVars = {'kpi', 'verification', 'params'};
for i = 1:numel(requiredBaseVars)
    if ~isfield(baseData, requiredBaseVars{i})
        error('compare_caseB_base_vs_stacking:MissingBaseVar', ...
            'Missing variable "%s" in base case workspace.', requiredBaseVars{i});
    end
end

requiredStackVars = {'kpi', 'verification', 'params'};
for i = 1:numel(requiredStackVars)
    if ~isfield(stackData, requiredStackVars{i})
        error('compare_caseB_base_vs_stacking:MissingStackVar', ...
            'Missing variable "%s" in stacking case workspace.', requiredStackVars{i});
    end
end

baseKPI = baseData.kpi;
baseVerification = baseData.verification;

stackKPI = stackData.kpi;
stackVerification = stackData.verification;

%% 3. Build aligned comparison metrics
% Notes:
% - For base case, "TotalRevenue" is just arbitrage profit
% - For stacking case, "TotalRevenue" includes arbitrage + ancillary revenue
% - Base case has no ancillary revenue and no reserve metrics

metricNames = { ...
    'TotalRevenue_GBP'
    'ArbitrageRevenue_GBP'
    'AncillaryRevenue_GBP'
    'AncillaryRevenueShare'
    'TotalCharge_kWh'
    'TotalDischarge_kWh'
    'EnergyThroughput_kWh'
    'SOCmin_kWh'
    'SOCmax_kWh'
    'SOCmean_kWh'
    'SOCfinal_kWh'
    'ChargeHours'
    'DischargeHours'
    'IdleHours'
    'ReserveActiveHours'
    'AvgReservedCapacity_kW'
    'MaxReservedCapacity_kW'
    'EquivalentFullCycles'
    'EquivalentCyclesDischargeBased'
    'AvgChargePrice_GBPperKWh'
    'AvgDischargePrice_GBPperKWh'
    'RevenuePerThroughput_GBPperKWh'
    'AllCoreChecksPass'
    };

baseValues = [ ...
    baseKPI.total_profit_gbp
    baseKPI.total_profit_gbp
    0
    0
    baseKPI.total_charge_kwh
    baseKPI.total_discharge_kwh
    baseKPI.energy_throughput_kwh
    baseKPI.soc_min_kwh
    baseKPI.soc_max_kwh
    baseKPI.soc_mean_kwh
    baseKPI.soc_final_kwh
    baseKPI.charge_hours
    baseKPI.discharge_hours
    baseKPI.idle_hours
    0
    0
    0
    baseKPI.equivalent_full_cycles
    baseKPI.equivalent_cycles_discharge_based
    baseKPI.avg_charge_price_gbp_per_kwh
    baseKPI.avg_discharge_price_gbp_per_kwh
    baseKPI.profit_per_throughput_gbp_per_kwh
    double(baseVerification.all_core_checks_pass)
    ];

stackValues = [ ...
    stackKPI.total_revenue_gbp
    stackKPI.arbitrage_revenue_gbp
    stackKPI.ancillary_revenue_gbp
    stackKPI.ancillary_revenue_share
    stackKPI.total_charge_kwh
    stackKPI.total_discharge_kwh
    stackKPI.energy_throughput_kwh
    stackKPI.soc_min_kwh
    stackKPI.soc_max_kwh
    stackKPI.soc_mean_kwh
    stackKPI.soc_final_kwh
    stackKPI.charge_hours
    stackKPI.discharge_hours
    stackKPI.idle_hours
    stackKPI.reserve_active_hours
    stackKPI.avg_reserved_capacity_kw
    stackKPI.max_reserved_capacity_kw
    stackKPI.equivalent_full_cycles
    stackKPI.equivalent_cycles_discharge_based
    stackKPI.avg_charge_price_gbp_per_kwh
    stackKPI.avg_discharge_price_gbp_per_kwh
    stackKPI.revenue_per_throughput_gbp_per_kwh
    double(stackVerification.all_core_checks_pass)
    ];

absoluteChange = stackValues - baseValues;

percentChange = nan(size(baseValues));
for i = 1:numel(baseValues)
    if abs(baseValues(i)) > 1e-12
        percentChange(i) = 100 * (stackValues(i) - baseValues(i)) / baseValues(i);
    else
        percentChange(i) = NaN;
    end
end

%% 4. Create main comparison table
comparisonTable = table( ...
    string(metricNames), ...
    baseValues, ...
    stackValues, ...
    absoluteChange, ...
    percentChange, ...
    'VariableNames', { ...
    'Metric', ...
    'BaseCase', ...
    'StackingCase', ...
    'AbsoluteChange', ...
    'PercentChange'});

%% 5. Create a smaller report-focused summary table
reportMetricNames = { ...
    'Total revenue / profit (GBP)'
    'Arbitrage revenue (GBP)'
    'Ancillary revenue (GBP)'
    'Ancillary revenue share'
    'Energy throughput (kWh)'
    'Charge hours'
    'Discharge hours'
    'Reserve active hours'
    'Equivalent full cycles'
    'Average charge price (GBP/kWh)'
    'Average discharge price (GBP/kWh)'
    'Average reserved capacity (kW)'
    'All core checks pass'
    };

reportBase = [ ...
    baseKPI.total_profit_gbp
    baseKPI.total_profit_gbp
    0
    0
    baseKPI.energy_throughput_kwh
    baseKPI.charge_hours
    baseKPI.discharge_hours
    0
    baseKPI.equivalent_full_cycles
    baseKPI.avg_charge_price_gbp_per_kwh
    baseKPI.avg_discharge_price_gbp_per_kwh
    0
    double(baseVerification.all_core_checks_pass)
    ];

reportStack = [ ...
    stackKPI.total_revenue_gbp
    stackKPI.arbitrage_revenue_gbp
    stackKPI.ancillary_revenue_gbp
    stackKPI.ancillary_revenue_share
    stackKPI.energy_throughput_kwh
    stackKPI.charge_hours
    stackKPI.discharge_hours
    stackKPI.reserve_active_hours
    stackKPI.equivalent_full_cycles
    stackKPI.avg_charge_price_gbp_per_kwh
    stackKPI.avg_discharge_price_gbp_per_kwh
    stackKPI.avg_reserved_capacity_kw
    double(stackVerification.all_core_checks_pass)
    ];

reportAbsChange = reportStack - reportBase;
reportPctChange = nan(size(reportBase));
for i = 1:numel(reportBase)
    if abs(reportBase(i)) > 1e-12
        reportPctChange(i) = 100 * (reportStack(i) - reportBase(i)) / reportBase(i);
    else
        reportPctChange(i) = NaN;
    end
end

reportTable = table( ...
    string(reportMetricNames), ...
    reportBase, ...
    reportStack, ...
    reportAbsChange, ...
    reportPctChange, ...
    'VariableNames', { ...
    'Metric', ...
    'BaseCase', ...
    'StackingCase', ...
    'AbsoluteChange', ...
    'PercentChange'});

%% 6. Save tables
writetable(comparisonTable, fullfile(outputDir, 'caseB_base_vs_stacking_comparison.csv'));
writetable(reportTable, fullfile(outputDir, 'caseB_base_vs_stacking_report_summary.csv'));

%% 7. Print key findings
fprintf('\n============= BASE VS STACKING SUMMARY =============\n');

fprintf('Base case total profit           : %.4f GBP\n', baseKPI.total_profit_gbp);
fprintf('Stacking total revenue           : %.4f GBP\n', stackKPI.total_revenue_gbp);
fprintf('Absolute revenue increase        : %.4f GBP\n', ...
    stackKPI.total_revenue_gbp - baseKPI.total_profit_gbp);
fprintf('Percentage revenue increase      : %.2f %%\n', ...
    100 * (stackKPI.total_revenue_gbp - baseKPI.total_profit_gbp) / baseKPI.total_profit_gbp);

fprintf('\nBase case arbitrage revenue      : %.4f GBP\n', baseKPI.total_profit_gbp);
fprintf('Stacking arbitrage revenue       : %.4f GBP\n', stackKPI.arbitrage_revenue_gbp);
fprintf('Stacking ancillary revenue       : %.4f GBP\n', stackKPI.ancillary_revenue_gbp);
fprintf('Ancillary revenue share          : %.4f\n', stackKPI.ancillary_revenue_share);

fprintf('\nBase throughput                  : %.4f kWh\n', baseKPI.energy_throughput_kwh);
fprintf('Stacking throughput              : %.4f kWh\n', stackKPI.energy_throughput_kwh);
fprintf('Throughput change                : %.2f %%\n', ...
    100 * (stackKPI.energy_throughput_kwh - baseKPI.energy_throughput_kwh) / baseKPI.energy_throughput_kwh);

fprintf('\nBase equivalent full cycles      : %.4f\n', baseKPI.equivalent_full_cycles);
fprintf('Stacking equivalent full cycles  : %.4f\n', stackKPI.equivalent_full_cycles);
fprintf('Cycle change                     : %.2f %%\n', ...
    100 * (stackKPI.equivalent_full_cycles - baseKPI.equivalent_full_cycles) / baseKPI.equivalent_full_cycles);

fprintf('\nBase charge / discharge hours    : %d / %d\n', ...
    baseKPI.charge_hours, baseKPI.discharge_hours);
fprintf('Stack charge / discharge / reserve hrs: %d / %d / %d\n', ...
    stackKPI.charge_hours, stackKPI.discharge_hours, stackKPI.reserve_active_hours);

fprintf('\nBase avg charge / discharge price: %.6f / %.6f GBP/kWh\n', ...
    baseKPI.avg_charge_price_gbp_per_kwh, baseKPI.avg_discharge_price_gbp_per_kwh);
fprintf('Stack avg charge / discharge price: %.6f / %.6f GBP/kWh\n', ...
    stackKPI.avg_charge_price_gbp_per_kwh, stackKPI.avg_discharge_price_gbp_per_kwh);

fprintf('\nBase all core checks pass        : %d\n', double(baseVerification.all_core_checks_pass));
fprintf('Stack all core checks pass       : %d\n', double(stackVerification.all_core_checks_pass));

fprintf('Comparison tables saved to       : %s\n', outputDir);
fprintf('====================================================\n\n');

%% 8. Save a MAT file with comparison results
save(fullfile(outputDir, 'caseB_base_vs_stacking_comparison.mat'), ...
    'comparisonTable', 'reportTable', ...
    'baseKPI', 'stackKPI', 'baseVerification', 'stackVerification');

fprintf('Comparison MAT file saved successfully.\n');