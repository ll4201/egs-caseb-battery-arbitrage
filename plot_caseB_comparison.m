%% plot_caseB_comparison.m
% Plot comparison figures for Case B:
% Base case vs Market Stacking extension
%
% This script:
% 1) Loads saved .mat workspaces
% 2) Extracts key KPIs
% 3) Generates report-friendly comparison figures
% 4) Saves figures to results_comparison/figures
%
% Expected input files:
%   results/caseB_basecase_workspace.mat
%   results_stacking/caseB_stacking_workspace.mat

clear; clc; close all;

%% 0. User settings
baseMatFile = fullfile('results', 'caseB_basecase_workspace.mat');
stackMatFile = fullfile('results_stacking', 'caseB_stacking_workspace.mat');

outputDir = 'results_comparison';
figDir = fullfile(outputDir, 'figures');
saveFigures = true;

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
if ~exist(figDir, 'dir')
    mkdir(figDir);
end

%% 1. Load saved workspaces
fprintf('Loading base case workspace...\n');
if ~isfile(baseMatFile)
    error('plot_caseB_comparison:BaseFileNotFound', ...
        'Base case workspace not found: %s', baseMatFile);
end
baseData = load(baseMatFile);

fprintf('Loading stacking case workspace...\n');
if ~isfile(stackMatFile)
    error('plot_caseB_comparison:StackFileNotFound', ...
        'Stacking case workspace not found: %s', stackMatFile);
end
stackData = load(stackMatFile);

%% 2. Check required variables
requiredBaseVars = {'kpi', 'verification'};
for i = 1:numel(requiredBaseVars)
    if ~isfield(baseData, requiredBaseVars{i})
        error('plot_caseB_comparison:MissingBaseVar', ...
            'Missing variable "%s" in base case workspace.', requiredBaseVars{i});
    end
end

requiredStackVars = {'kpi', 'verification'};
for i = 1:numel(requiredStackVars)
    if ~isfield(stackData, requiredStackVars{i})
        error('plot_caseB_comparison:MissingStackVar', ...
            'Missing variable "%s" in stacking case workspace.', requiredStackVars{i});
    end
end

baseKPI = baseData.kpi;
stackKPI = stackData.kpi;

%% 3. Figure 1: Total revenue / profit comparison
fig1 = figure('Name', 'Comparison - Total Revenue', 'NumberTitle', 'off');
categories1 = categorical({'Base case', 'Stacking'});
values1 = [baseKPI.total_profit_gbp, stackKPI.total_revenue_gbp];

bar(categories1, values1);
grid on;
ylabel('Revenue / Profit (GBP)');
title('Base case profit vs stacking total revenue');

if saveFigures
    saveFigureCompat(fig1, figDir, 'fig1_total_revenue_comparison');
end

%% 4. Figure 2: Stacking revenue breakdown
fig2 = figure('Name', 'Comparison - Stacking Revenue Breakdown', 'NumberTitle', 'off');
categories2 = categorical({'Arbitrage', 'Ancillary', 'Total'});
values2 = [stackKPI.arbitrage_revenue_gbp, ...
           stackKPI.ancillary_revenue_gbp, ...
           stackKPI.total_revenue_gbp];

bar(categories2, values2);
grid on;
ylabel('Revenue (GBP)');
title('Stacking revenue breakdown');

if saveFigures
    saveFigureCompat(fig2, figDir, 'fig2_stacking_revenue_breakdown');
end

%% 5. Figure 3: Throughput comparison
fig3 = figure('Name', 'Comparison - Energy Throughput', 'NumberTitle', 'off');
categories3 = categorical({'Base case', 'Stacking'});
values3 = [baseKPI.energy_throughput_kwh, stackKPI.energy_throughput_kwh];

bar(categories3, values3);
grid on;
ylabel('Energy throughput (kWh)');
title('Energy throughput comparison');

if saveFigures
    saveFigureCompat(fig3, figDir, 'fig3_throughput_comparison');
end

%% 6. Figure 4: Equivalent full cycles comparison
fig4 = figure('Name', 'Comparison - Equivalent Full Cycles', 'NumberTitle', 'off');
categories4 = categorical({'Base case', 'Stacking'});
values4 = [baseKPI.equivalent_full_cycles, stackKPI.equivalent_full_cycles];

bar(categories4, values4);
grid on;
ylabel('Equivalent full cycles');
title('Equivalent full cycle comparison');

if saveFigures
    saveFigureCompat(fig4, figDir, 'fig4_cycle_comparison');
end

%% 7. Figure 5: Operating hours comparison
fig5 = figure('Name', 'Comparison - Operating Hours', 'NumberTitle', 'off');

hourCategories = categorical({'Charge hours', 'Discharge hours', 'Idle hours', 'Reserve hours'});
hourCategories = reordercats(hourCategories, {'Charge hours', 'Discharge hours', 'Idle hours', 'Reserve hours'});

baseHours = [baseKPI.charge_hours, baseKPI.discharge_hours, baseKPI.idle_hours, 0];
stackHours = [stackKPI.charge_hours, stackKPI.discharge_hours, stackKPI.idle_hours, stackKPI.reserve_active_hours];

hourMatrix = [baseHours; stackHours]';

bar(hourCategories, hourMatrix);
grid on;
ylabel('Hours');
title('Operating hours comparison');
legend({'Base case', 'Stacking'}, 'Location', 'best');

if saveFigures
    saveFigureCompat(fig5, figDir, 'fig5_operating_hours_comparison');
end

%% 8. Figure 6: Average charge/discharge price comparison
fig6 = figure('Name', 'Comparison - Average Charge and Discharge Prices', 'NumberTitle', 'off');

priceCategories = categorical({'Avg charge price', 'Avg discharge price'});
priceCategories = reordercats(priceCategories, {'Avg charge price', 'Avg discharge price'});

basePrices = [baseKPI.avg_charge_price_gbp_per_kwh, baseKPI.avg_discharge_price_gbp_per_kwh];
stackPrices = [stackKPI.avg_charge_price_gbp_per_kwh, stackKPI.avg_discharge_price_gbp_per_kwh];

priceMatrix = [basePrices; stackPrices]';

bar(priceCategories, priceMatrix);
grid on;
ylabel('Price (GBP/kWh)');
title('Average charge and discharge price comparison');
legend({'Base case', 'Stacking'}, 'Location', 'best');

if saveFigures
    saveFigureCompat(fig6, figDir, 'fig6_avg_price_comparison');
end

%% 9. Print summary
fprintf('\n--- Comparison plotting summary ---\n');
fprintf('Generated Figure 1: total revenue / profit comparison\n');
fprintf('Generated Figure 2: stacking revenue breakdown\n');
fprintf('Generated Figure 3: energy throughput comparison\n');
fprintf('Generated Figure 4: equivalent full cycles comparison\n');
fprintf('Generated Figure 5: operating hours comparison\n');
fprintf('Generated Figure 6: average charge/discharge price comparison\n');

if saveFigures
    fprintf('Figures saved to: %s\n', figDir);
else
    fprintf('Figures were generated but not saved.\n');
end
fprintf('-----------------------------------\n\n');

%% ===== Helper function =====
function saveFigureCompat(figHandle, figDir, baseName)
% Save figure with compatibility for different MATLAB versions

    pngFile = fullfile(figDir, [baseName, '.png']);
    figFile = fullfile(figDir, [baseName, '.fig']);

    try
        exportgraphics(figHandle, pngFile, 'Resolution', 300);
    catch
        saveas(figHandle, pngFile);
    end

    try
        savefig(figHandle, figFile);
    catch
        % Older versions may not support savefig robustly in all cases
    end
end