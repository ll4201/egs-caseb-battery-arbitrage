function kpi = compute_kpis(data, params, solution)
% compute_kpis
% Compute key performance indicators (KPIs) for Case B:
% grid-scale battery arbitrage in the day-ahead market.
%
% INPUTS:
%   data      - struct returned by read_caseB_data
%   params    - parameter struct from main_caseB
%   solution  - struct returned by solve_caseB_lp
%
% OUTPUT:
%   kpi       - struct containing key metrics for reporting and analysis
%
% Main reported KPIs include:
%   kpi.total_profit_gbp
%   kpi.total_charge_kwh
%   kpi.total_discharge_kwh
%   kpi.energy_throughput_kwh
%   kpi.soc_min_kwh
%   kpi.soc_max_kwh
%   kpi.soc_final_kwh
%
% Additional diagnostic metrics are also included to support:
%   - engineering insights
%   - verification
%   - extension comparison later

    %% 1. Basic input checks
    requiredDataFields = {'price_kwh', 'N', 'dt'};
    for i = 1:numel(requiredDataFields)
        if ~isfield(data, requiredDataFields{i})
            error('compute_kpis:MissingDataField', ...
                'Missing required field data.%s', requiredDataFields{i});
        end
    end

    requiredParamFields = {'SOC_init', 'Emax'};
    for i = 1:numel(requiredParamFields)
        if ~isfield(params, requiredParamFields{i})
            error('compute_kpis:MissingParamField', ...
                'Missing required field params.%s', requiredParamFields{i});
        end
    end

    requiredSolutionFields = {'Pch', 'Pdis', 'SOC', 'profit_opt'};
    for i = 1:numel(requiredSolutionFields)
        if ~isfield(solution, requiredSolutionFields{i})
            error('compute_kpis:MissingSolutionField', ...
                'Missing required field solution.%s', requiredSolutionFields{i});
        end
    end

    N = data.N;
    dt = data.dt;
    price = data.price_kwh(:);

    Pch = solution.Pch(:);
    Pdis = solution.Pdis(:);
    SOC = solution.SOC(:);

    if numel(Pch) ~= N || numel(Pdis) ~= N || numel(SOC) ~= N
        error('compute_kpis:DimensionMismatch', ...
            'Dimensions of Pch, Pdis, or SOC do not match data.N.');
    end

    %% 2. Energy quantities
    % Since power is in kW and dt is in hours:
    %   Energy [kWh] = Power [kW] * dt [h]
    charge_energy_each_step_kwh = Pch * dt;
    discharge_energy_each_step_kwh = Pdis * dt;

    total_charge_kwh = sum(charge_energy_each_step_kwh);
    total_discharge_kwh = sum(discharge_energy_each_step_kwh);

    % Throughput definition used here:
    % total bidirectional energy processed by the battery
    energy_throughput_kwh = total_charge_kwh + total_discharge_kwh;

    %% 3. Profit calculation
    % Profit at each time step:
    %   price * (Pdis - Pch) * dt
    profit_each_step_gbp = price .* (Pdis - Pch) * dt;
    total_profit_gbp_recomputed = sum(profit_each_step_gbp);

    % Also keep the value reported from the optimisation
    total_profit_gbp = solution.profit_opt;

    %% 4. SOC summary
    soc_min_kwh = min(SOC);
    soc_max_kwh = max(SOC);
    soc_mean_kwh = mean(SOC);
    soc_final_kwh = SOC(end);
    soc_initial_kwh_from_solution = SOC(1);

    % Convert SOC to percentage of usable energy capacity
    soc_pct = 100 * SOC / params.Emax;
    soc_min_pct = min(soc_pct);
    soc_max_pct = max(soc_pct);
    soc_mean_pct = mean(soc_pct);
    soc_final_pct = soc_pct(end);

    %% 5. Time-activity summary
    tol = 1e-8;

    charge_hours = sum(Pch > tol);
    discharge_hours = sum(Pdis > tol);
    idle_hours = sum((Pch <= tol) & (Pdis <= tol));
    simultaneous_charge_discharge_hours = sum((Pch > tol) & (Pdis > tol));

    %% 6. Average and peak operating levels
    peak_charge_power_kw = max(Pch);
    peak_discharge_power_kw = max(Pdis);

    avg_charge_power_when_active_kw = 0;
    if charge_hours > 0
        avg_charge_power_when_active_kw = mean(Pch(Pch > tol));
    end

    avg_discharge_power_when_active_kw = 0;
    if discharge_hours > 0
        avg_discharge_power_when_active_kw = mean(Pdis(Pdis > tol));
    end

    %% 7. Cycling-style indicators
    % A simple equivalent full cycle estimate can be built from throughput.
    %
    % One full cycle roughly corresponds to:
    %   charge Emax and discharge Emax => throughput = 2*Emax
    %
    % So:
    %   equivalent full cycles = throughput / (2*Emax)
    equivalent_full_cycles = energy_throughput_kwh / (2 * params.Emax);

    % Another common indicator is discharge-based equivalent cycles:
    equivalent_cycles_discharge_based = total_discharge_kwh / params.Emax;

    %% 8. Simple economic intensity indicators
    profit_per_throughput_gbp_per_kwh = 0;
    if energy_throughput_kwh > 0
        profit_per_throughput_gbp_per_kwh = total_profit_gbp / energy_throughput_kwh;
    end

    profit_per_discharge_gbp_per_kwh = 0;
    if total_discharge_kwh > 0
        profit_per_discharge_gbp_per_kwh = total_profit_gbp / total_discharge_kwh;
    end

    %% 9. Price-response indicators
    % Compute simple descriptive statistics for times when the battery is active.
    avg_price_all_gbp_per_kwh = mean(price);

    avg_charge_price_gbp_per_kwh = NaN;
    if charge_hours > 0
        avg_charge_price_gbp_per_kwh = mean(price(Pch > tol));
    end

    avg_discharge_price_gbp_per_kwh = NaN;
    if discharge_hours > 0
        avg_discharge_price_gbp_per_kwh = mean(price(Pdis > tol));
    end

    %% 10. Energy balance style summaries
    % These are not physical loss calculations directly from SOC recursion,
    % but they are useful descriptive indicators.
    net_grid_energy_bought_kwh = total_charge_kwh;
    net_grid_energy_sold_kwh = total_discharge_kwh;
    net_export_minus_import_kwh = total_discharge_kwh - total_charge_kwh;

    %% 11. Package outputs
    kpi = struct();

    % Core coursework KPIs
    kpi.total_profit_gbp = total_profit_gbp;
    kpi.total_profit_gbp_recomputed = total_profit_gbp_recomputed;
    kpi.total_charge_kwh = total_charge_kwh;
    kpi.total_discharge_kwh = total_discharge_kwh;
    kpi.energy_throughput_kwh = energy_throughput_kwh;

    kpi.soc_min_kwh = soc_min_kwh;
    kpi.soc_max_kwh = soc_max_kwh;
    kpi.soc_mean_kwh = soc_mean_kwh;
    kpi.soc_final_kwh = soc_final_kwh;
    kpi.soc_initial_kwh_from_solution = soc_initial_kwh_from_solution;

    kpi.soc_min_pct = soc_min_pct;
    kpi.soc_max_pct = soc_max_pct;
    kpi.soc_mean_pct = soc_mean_pct;
    kpi.soc_final_pct = soc_final_pct;

    % Activity summaries
    kpi.charge_hours = charge_hours;
    kpi.discharge_hours = discharge_hours;
    kpi.idle_hours = idle_hours;
    kpi.simultaneous_charge_discharge_hours = simultaneous_charge_discharge_hours;

    % Power summaries
    kpi.peak_charge_power_kw = peak_charge_power_kw;
    kpi.peak_discharge_power_kw = peak_discharge_power_kw;
    kpi.avg_charge_power_when_active_kw = avg_charge_power_when_active_kw;
    kpi.avg_discharge_power_when_active_kw = avg_discharge_power_when_active_kw;

    % Cycling / utilisation
    kpi.equivalent_full_cycles = equivalent_full_cycles;
    kpi.equivalent_cycles_discharge_based = equivalent_cycles_discharge_based;

    % Economic intensity
    kpi.profit_per_throughput_gbp_per_kwh = profit_per_throughput_gbp_per_kwh;
    kpi.profit_per_discharge_gbp_per_kwh = profit_per_discharge_gbp_per_kwh;

    % Price-response summaries
    kpi.avg_price_all_gbp_per_kwh = avg_price_all_gbp_per_kwh;
    kpi.avg_charge_price_gbp_per_kwh = avg_charge_price_gbp_per_kwh;
    kpi.avg_discharge_price_gbp_per_kwh = avg_discharge_price_gbp_per_kwh;

    % Market-energy summaries
    kpi.net_grid_energy_bought_kwh = net_grid_energy_bought_kwh;
    kpi.net_grid_energy_sold_kwh = net_grid_energy_sold_kwh;
    kpi.net_export_minus_import_kwh = net_export_minus_import_kwh;

    % Time-series values for later plotting or analysis
    kpi.charge_energy_each_step_kwh = charge_energy_each_step_kwh;
    kpi.discharge_energy_each_step_kwh = discharge_energy_each_step_kwh;
    kpi.profit_each_step_gbp = profit_each_step_gbp;
    kpi.soc_pct = soc_pct;

    %% 12. Print summary
    fprintf('\n--- KPI summary ---\n');
    fprintf('Total profit                  : %.6f GBP\n', kpi.total_profit_gbp);
    fprintf('Recomputed profit             : %.6f GBP\n', kpi.total_profit_gbp_recomputed);
    fprintf('Total charge energy           : %.6f kWh\n', kpi.total_charge_kwh);
    fprintf('Total discharge energy        : %.6f kWh\n', kpi.total_discharge_kwh);
    fprintf('Energy throughput             : %.6f kWh\n', kpi.energy_throughput_kwh);
    fprintf('SOC min / mean / max          : %.6f / %.6f / %.6f kWh\n', ...
        kpi.soc_min_kwh, kpi.soc_mean_kwh, kpi.soc_max_kwh);
    fprintf('Initial / final SOC           : %.6f / %.6f kWh\n', ...
        kpi.soc_initial_kwh_from_solution, kpi.soc_final_kwh);
    fprintf('Charge / discharge / idle hrs : %d / %d / %d\n', ...
        kpi.charge_hours, kpi.discharge_hours, kpi.idle_hours);
    fprintf('Equivalent full cycles        : %.6f\n', kpi.equivalent_full_cycles);

    if ~isnan(kpi.avg_charge_price_gbp_per_kwh)
        fprintf('Avg charge price              : %.6f GBP/kWh\n', ...
            kpi.avg_charge_price_gbp_per_kwh);
    else
        fprintf('Avg charge price              : N/A\n');
    end

    if ~isnan(kpi.avg_discharge_price_gbp_per_kwh)
        fprintf('Avg discharge price           : %.6f GBP/kWh\n', ...
            kpi.avg_discharge_price_gbp_per_kwh);
    else
        fprintf('Avg discharge price           : N/A\n');
    end

    fprintf('--------------------\n\n');
end