function plot_caseB_results(data, params, solution, kpi, figDir, saveFigures)
% plot_caseB_results
% Further improved plotting function for Case B battery arbitrage coursework.
%
% INPUTS:
%   data         - struct returned by read_caseB_data
%   params       - parameter struct from main_caseB
%   solution     - struct returned by solve_caseB_lp
%   kpi          - struct returned by compute_kpis
%   figDir       - folder for saving figures
%   saveFigures  - logical flag, true to save figures
%
% Figures generated:
%   1) Full-horizon day-ahead price time series
%   2) Daily net energy exchange
%   3) Daily average SOC
%   4) Zoomed operational window (price / charge-discharge / SOC)
%   5) Energy and SOC summary bar chart
%   6) Cumulative profit over time
%
% Notes:
% - Daily net energy is defined as:
%       sum_over_day (Pdis - Pch) * dt
%   positive  -> net discharge / net export from battery to market
%   negative  -> net charge / net import into battery
% - Daily average SOC is the mean SOC within each day.

    %% 1. Basic input checks
    if nargin < 6
        saveFigures = false;
    end

    if nargin < 5 || isempty(figDir)
        figDir = 'results';
    end

    requiredDataFields = {'time', 'price_mwh', 'N', 'dt'};
    for i = 1:numel(requiredDataFields)
        if ~isfield(data, requiredDataFields{i})
            error('plot_caseB_results:MissingDataField', ...
                'Missing required field data.%s', requiredDataFields{i});
        end
    end

    requiredParamFields = {'Emax', 'SOC_init'};
    for i = 1:numel(requiredParamFields)
        if ~isfield(params, requiredParamFields{i})
            error('plot_caseB_results:MissingParamField', ...
                'Missing required field params.%s', requiredParamFields{i});
        end
    end

    requiredSolutionFields = {'Pch', 'Pdis', 'SOC'};
    for i = 1:numel(requiredSolutionFields)
        if ~isfield(solution, requiredSolutionFields{i})
            error('plot_caseB_results:MissingSolutionField', ...
                'Missing required field solution.%s', requiredSolutionFields{i});
        end
    end

    requiredKpiFields = {'profit_each_step_gbp', ...
                         'total_charge_kwh', 'total_discharge_kwh', ...
                         'energy_throughput_kwh', ...
                         'soc_min_kwh', 'soc_max_kwh'};
    for i = 1:numel(requiredKpiFields)
        if ~isfield(kpi, requiredKpiFields{i})
            error('plot_caseB_results:MissingKPIField', ...
                'Missing required field kpi.%s', requiredKpiFields{i});
        end
    end

    if saveFigures && ~exist(figDir, 'dir')
        mkdir(figDir);
    end

    %% 2. Extract data
    t = data.time(:);
    price_mwh = data.price_mwh(:);

    Pch = solution.Pch(:);
    Pdis = solution.Pdis(:);
    SOC = solution.SOC(:);

    profit_each_step_gbp = kpi.profit_each_step_gbp(:);

    N = data.N;
    dt = data.dt;

    if numel(t) ~= N || numel(price_mwh) ~= N || ...
       numel(Pch) ~= N || numel(Pdis) ~= N || ...
       numel(SOC) ~= N || numel(profit_each_step_gbp) ~= N
        error('plot_caseB_results:DimensionMismatch', ...
            'One or more plotting vectors do not match data.N.');
    end

    %% 3. Derived series
    Pnet = Pdis - Pch;                         % kW
    netEnergyEachStep = Pnet * dt;             % kWh per step
    cumulative_profit_gbp = cumsum(profit_each_step_gbp);

    %% 4. Daily aggregation
    % Convert timestamps to day groups
    dayStamp = dateshift(t, 'start', 'day');
    [uniqueDays, ~, dayIdx] = unique(dayStamp);

    nDays = numel(uniqueDays);

    daily_net_energy_kwh = accumarray(dayIdx, netEnergyEachStep, [nDays, 1], @sum, 0);
    daily_avg_soc_kwh = accumarray(dayIdx, SOC, [nDays, 1], @mean, NaN);
    daily_min_soc_kwh = accumarray(dayIdx, SOC, [nDays, 1], @min, NaN);
    daily_max_soc_kwh = accumarray(dayIdx, SOC, [nDays, 1], @max, NaN);

    %% 5. Decide zoom window
    % Use a representative 4-day window centered on the largest absolute price event
    zoomLength = min(96, N);

    [~, peakIdx] = max(abs(price_mwh));

    if N <= zoomLength
        zoomStart = 1;
        zoomEnd = N;
    else
        zoomStart = max(1, peakIdx - floor(zoomLength / 2));
        zoomEnd = min(N, zoomStart + zoomLength - 1);
        zoomStart = max(1, zoomEnd - zoomLength + 1);
    end

    tz = t(zoomStart:zoomEnd);
    priceZoom = price_mwh(zoomStart:zoomEnd);
    PchZoom = Pch(zoomStart:zoomEnd);
    PdisZoom = Pdis(zoomStart:zoomEnd);
    SOCZoom = SOC(zoomStart:zoomEnd);

    %% 6. Figure 1: full-horizon day-ahead price
    fig1 = figure('Name', 'Case B - Day-Ahead Price', 'NumberTitle', 'off');
    plot(t, price_mwh, 'LineWidth', 1.0);
    grid on;
    xlabel('Time');
    ylabel('Day-ahead price (GBP/MWh)');
    title('Day-ahead electricity price over the full horizon');

    if saveFigures
        saveFigureCompat(fig1, figDir, 'fig1_price_full_horizon');
    end

    %% 7. Figure 2: daily net energy exchange
    fig2 = figure('Name', 'Case B - Daily Net Energy Exchange', 'NumberTitle', 'off');
    bar(uniqueDays, daily_net_energy_kwh);
    hold on;
    yline(0, '--', 'LineWidth', 0.8);
    hold off;
    grid on;
    xlabel('Day');
    ylabel('Daily net energy (kWh)');
    title('Daily net energy exchange of the battery');
    legend({'Net energy', 'Zero line'}, 'Location', 'best');

    if saveFigures
        saveFigureCompat(fig2, figDir, 'fig2_daily_net_energy');
    end

    %% 8. Figure 3: daily average SOC
    fig3 = figure('Name', 'Case B - Daily Average SOC', 'NumberTitle', 'off');
    plot(uniqueDays, daily_avg_soc_kwh, 'LineWidth', 1.1);
    hold on;
    plot(uniqueDays, daily_min_soc_kwh, ':', 'LineWidth', 0.9);
    plot(uniqueDays, daily_max_soc_kwh, ':', 'LineWidth', 0.9);
    yline(params.SOC_init, '--', 'LineWidth', 0.8);
    hold off;
    grid on;
    xlabel('Day');
    ylabel('SOC (kWh)');
    title('Daily average, minimum, and maximum SOC');
    legend({'Daily average SOC', 'Daily minimum SOC', 'Daily maximum SOC', 'Initial SOC'}, ...
        'Location', 'best');

    ylim([0, max(params.Emax * 1.05, max(daily_max_soc_kwh) * 1.05)]);

    if saveFigures
        saveFigureCompat(fig3, figDir, 'fig3_daily_average_soc');
    end

    %% 9. Figure 4: zoomed operational window
    fig4 = figure('Name', 'Case B - Zoomed Operational Window', 'NumberTitle', 'off');
    tiledlayout(3,1, 'Padding', 'compact', 'TileSpacing', 'compact');

    % (a) Price
    nexttile;
    plot(tz, priceZoom, 'LineWidth', 1.0);
    grid on;
    ylabel('GBP/MWh');
    title(sprintf('Zoomed operational window (%d to %d)', zoomStart, zoomEnd));

    % (b) Charge and discharge power
    nexttile;
    hold on;
    stairs(tz, PchZoom, 'LineWidth', 1.0);
    stairs(tz, PdisZoom, 'LineWidth', 1.0);
    hold off;
    grid on;
    ylabel('Power (kW)');
    legend({'Charge power', 'Discharge power'}, 'Location', 'best');

    % (c) SOC
    nexttile;
    plot(tz, SOCZoom, 'LineWidth', 1.1);
    hold on;
    yline(params.SOC_init, '--', 'Initial SOC', ...
        'LabelHorizontalAlignment', 'left');
    yline(params.Emax, ':', 'E_{max}', ...
        'LabelHorizontalAlignment', 'left');
    yline(0, ':', '0', ...
        'LabelHorizontalAlignment', 'left');
    hold off;
    grid on;
    xlabel('Time');
    ylabel('SOC (kWh)');

    if saveFigures
        saveFigureCompat(fig4, figDir, 'fig4_zoomed_operational_window');
    end

    %% 10. Figure 5: energy and SOC summary
    fig5 = figure('Name', 'Case B - Energy and SOC Summary', 'NumberTitle', 'off');

    metricNames = categorical({ ...
        'Charge (kWh)', ...
        'Discharge (kWh)', ...
        'Throughput (kWh)', ...
        'SOC min (kWh)', ...
        'SOC max (kWh)'});

    metricValues = [ ...
        kpi.total_charge_kwh, ...
        kpi.total_discharge_kwh, ...
        kpi.energy_throughput_kwh, ...
        kpi.soc_min_kwh, ...
        kpi.soc_max_kwh];

    bar(metricNames, metricValues);
    grid on;
    ylabel('Energy / SOC (kWh)');
    title('Energy and SOC summary');

    if saveFigures
        saveFigureCompat(fig5, figDir, 'fig5_energy_soc_summary');
    end

    %% 11. Figure 6: cumulative profit
    fig6 = figure('Name', 'Case B - Cumulative Profit', 'NumberTitle', 'off');
    plot(t, cumulative_profit_gbp, 'LineWidth', 1.1);
    grid on;
    xlabel('Time');
    ylabel('Cumulative profit (GBP)');
    title('Cumulative arbitrage profit over the full horizon');

    if saveFigures
        saveFigureCompat(fig6, figDir, 'fig6_cumulative_profit');
    end

    %% 12. Console summary
    fprintf('\n--- Plotting summary ---\n');
    fprintf('Generated Figure 1: full-horizon day-ahead price\n');
    fprintf('Generated Figure 2: daily net energy exchange\n');
    fprintf('Generated Figure 3: daily average SOC\n');
    fprintf('Generated Figure 4: zoomed operational window\n');
    fprintf('Generated Figure 5: energy and SOC summary\n');
    fprintf('Generated Figure 6: cumulative profit\n');

    if saveFigures
        fprintf('Figures saved to: %s\n', figDir);
    else
        fprintf('Figures were generated but not saved.\n');
    end
    fprintf('------------------------\n\n');
end

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