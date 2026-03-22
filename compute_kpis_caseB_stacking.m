function kpi = compute_kpis_caseB_stacking(data, params, solution)
% compute_kpis_caseB_stacking
% Compute key performance indicators (KPIs) for Case B extension:
% energy arbitrage + ancillary market stacking.
%
% INPUTS:
%   data      - struct returned by read_caseB_data
%   params    - parameter struct from main script
%   solution  - struct returned by solve_caseB_stacking_lp
%
% OUTPUT:
%   kpi       - struct containing key metrics for reporting and analysis
%
% Main reported KPIs include:
%   kpi.total_revenue_gbp
%   kpi.arbitrage_revenue_gbp
%   kpi.ancillary_revenue_gbp
%   kpi.total_charge_kwh
%   kpi.total_discharge_kwh
%   kpi.energy_throughput_kwh
%   kpi.soc_min_kwh
%   kpi.soc_max_kwh
%   kpi.soc_final_kwh
%   kpi.avg_reserved_capacity_kw
%   kpi.reserve_active_hours
%
% Notes:
% - This function mirrors the base-case KPI logic where possible.
% - It additionally quantifies reserve participation and revenue split.

    %% 1. Basic input checks
    requiredDataFields = {'price_kwh', 'ancillary_price_mw_h', 'N', 'dt'};
    for i = 1:numel(requiredDataFields)
        if ~isfield(data, requiredDataFields{i})
            error('compute_kpis_caseB_stacking:MissingDataField', ...
                'Missing required field data.%s', requiredDataFields{i});
        end
    end

    requiredParamFields = {'SOC_init', 'Emax', 'Pch_max', 'Pdis_max'};
    for i = 1:numel(requiredParamFields)
        if ~isfield(params, requiredParamFields{i})
            error('compute_kpis_caseB_stacking:MissingParamField', ...
                'Missing required field params.%s', requiredParamFields{i});
        end
    end

    requiredSolutionFields = {'Pch', 'Pdis', 'SOC', 'R', ...
                              'arbitrage_revenue_gbp', ...
                              'ancillary_revenue_gbp', ...
                              'total_revenue_gbp'};
    for i = 1:numel(requiredSolutionFields)
        if ~isfield(solution, requiredSolutionFields{i})
            error('compute_kpis_caseB_stacking:MissingSolutionField', ...
                'Missing required field solution.%s', requiredSolutionFields{i});
        end
    end

    N = data.N;
    dt = data.dt;

    price_DA = data.price_kwh(:);                % GBP/kWh
    price_anc = data.ancillary_price_mw_h(:);    % GBP/MW/h

    Pch = solution.Pch(:);
    Pdis = solution.Pdis(:);
    SOC = solution.SOC(:);
    R = solution.R(:);

    if numel(Pch) ~= N || numel(Pdis) ~= N || numel(SOC) ~= N || numel(R) ~= N
        error('compute_kpis_caseB_stacking:DimensionMismatch', ...
            'Dimensions of Pch, Pdis, SOC, or R do not match data.N.');
    end

    %% 2. Energy quantities
    charge_energy_each_step_kwh = Pch * dt;
    discharge_energy_each_step_kwh = Pdis * dt;
    reserve_capacity_each_step_kw = R;
    reserve_capacity_each_step_mw = R / 1000;

    total_charge_kwh = sum(charge_energy_each_step_kwh);
    total_discharge_kwh = sum(discharge_energy_each_step_kwh);
    energy_throughput_kwh = total_charge_kwh + total_discharge_kwh;

    %% 3. Revenue quantities
    arbitrage_revenue_each_step_gbp = price_DA .* (Pdis - Pch) * dt;
    ancillary_revenue_each_step_gbp = price_anc .* (R / 1000) * dt;

    arbitrage_revenue_gbp_recomputed = sum(arbitrage_revenue_each_step_gbp);
    ancillary_revenue_gbp_recomputed = sum(ancillary_revenue_each_step_gbp);
    total_revenue_gbp_recomputed = ...
        arbitrage_revenue_gbp_recomputed + ancillary_revenue_gbp_recomputed;

    arbitrage_revenue_gbp = solution.arbitrage_revenue_gbp;
    ancillary_revenue_gbp = solution.ancillary_revenue_gbp;
    total_revenue_gbp = solution.total_revenue_gbp;

    %% 4. SOC summary
    soc_min_kwh = min(SOC);
    soc_max_kwh = max(SOC);
    soc_mean_kwh = mean(SOC);
    soc_final_kwh = SOC(end);
    soc_initial_kwh_from_solution = SOC(1);

    soc_pct = 100 * SOC / params.Emax;
    soc_min_pct = min(soc_pct);
    soc_max_pct = max(soc_pct);
    soc_mean_pct = mean(soc_pct);
    soc_final_pct = soc_pct(end);

    %% 5. Reserve summary
    tol = 1e-8;

    reserve_active_hours = sum(R > tol);
    reserve_idle_hours = sum(R <= tol);

    avg_reserved_capacity_kw = mean(R);
    max_reserved_capacity_kw = max(R);

    avg_reserved_capacity_when_active_kw = 0;
    if reserve_active_hours > 0
        avg_reserved_capacity_when_active_kw = mean(R(R > tol));
    end

    % Time-integrated reserved capacity (capacity-hours)
    total_reserved_capacity_kwh_equiv = sum(R * dt);       % kW*h numerically equals kWh-equivalent
    total_reserved_capacity_mwh_equiv = total_reserved_capacity_kwh_equiv / 1000;

    % Reserve utilisation ratios relative to power capability
    avg_reserved_fraction_of_power_cap = avg_reserved_capacity_kw / min(params.Pch_max, params.Pdis_max);
    max_reserved_fraction_of_power_cap = max_reserved_capacity_kw / min(params.Pch_max, params.Pdis_max);

    %% 6. Activity summary
    charge_hours = sum(Pch > tol);
    discharge_hours = sum(Pdis > tol);
    idle_hours = sum((Pch <= tol) & (Pdis <= tol) & (R <= tol));

    simultaneous_charge_discharge_hours = sum((Pch > tol) & (Pdis > tol));
    simultaneous_charge_reserve_hours = sum((Pch > tol) & (R > tol));
    simultaneous_discharge_reserve_hours = sum((Pdis > tol) & (R > tol));

    %% 7. Power summaries
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

    %% 8. Cycling-style indicators
    equivalent_full_cycles = energy_throughput_kwh / (2 * params.Emax);
    equivalent_cycles_discharge_based = total_discharge_kwh / params.Emax;

    %% 9. Economic intensity indicators
    revenue_per_throughput_gbp_per_kwh = 0;
    if energy_throughput_kwh > 0
        revenue_per_throughput_gbp_per_kwh = total_revenue_gbp / energy_throughput_kwh;
    end

    arbitrage_revenue_per_discharge_gbp_per_kwh = 0;
    if total_discharge_kwh > 0
        arbitrage_revenue_per_discharge_gbp_per_kwh = arbitrage_revenue_gbp / total_discharge_kwh;
    end

    ancillary_revenue_per_reserved_mw_h = 0;
    if total_reserved_capacity_mwh_equiv > 0
        ancillary_revenue_per_reserved_mw_h = ancillary_revenue_gbp / total_reserved_capacity_mwh_equiv;
    end

    %% 10. Revenue share indicators
    if abs(total_revenue_gbp) > 0
        arbitrage_revenue_share = arbitrage_revenue_gbp / total_revenue_gbp;
        ancillary_revenue_share = ancillary_revenue_gbp / total_revenue_gbp;
    else
        arbitrage_revenue_share = NaN;
        ancillary_revenue_share = NaN;
    end

    %% 11. Price-response summaries
    avg_price_all_gbp_per_kwh = mean(price_DA);

    avg_charge_price_gbp_per_kwh = NaN;
    if charge_hours > 0
        avg_charge_price_gbp_per_kwh = mean(price_DA(Pch > tol));
    end

    avg_discharge_price_gbp_per_kwh = NaN;
    if discharge_hours > 0
        avg_discharge_price_gbp_per_kwh = mean(price_DA(Pdis > tol));
    end

    avg_ancillary_price_gbp_per_mw_h = mean(price_anc);

    avg_ancillary_price_when_reserved_gbp_per_mw_h = NaN;
    if reserve_active_hours > 0
        avg_ancillary_price_when_reserved_gbp_per_mw_h = mean(price_anc(R > tol));
    end

    %% 12. Market-energy summaries
    net_grid_energy_bought_kwh = total_charge_kwh;
    net_grid_energy_sold_kwh = total_discharge_kwh;
    net_export_minus_import_kwh = total_discharge_kwh - total_charge_kwh;

    %% 13. Pack outputs
    kpi = struct();

    % Core stacked revenue KPIs
    kpi.total_revenue_gbp = total_revenue_gbp;
    kpi.total_revenue_gbp_recomputed = total_revenue_gbp_recomputed;

    kpi.arbitrage_revenue_gbp = arbitrage_revenue_gbp;
    kpi.arbitrage_revenue_gbp_recomputed = arbitrage_revenue_gbp_recomputed;

    kpi.ancillary_revenue_gbp = ancillary_revenue_gbp;
    kpi.ancillary_revenue_gbp_recomputed = ancillary_revenue_gbp_recomputed;

    % Energy KPIs
    kpi.total_charge_kwh = total_charge_kwh;
    kpi.total_discharge_kwh = total_discharge_kwh;
    kpi.energy_throughput_kwh = energy_throughput_kwh;

    % SOC KPIs
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
    kpi.reserve_active_hours = reserve_active_hours;
    kpi.reserve_idle_hours = reserve_idle_hours;
    kpi.idle_hours = idle_hours;

    kpi.simultaneous_charge_discharge_hours = simultaneous_charge_discharge_hours;
    kpi.simultaneous_charge_reserve_hours = simultaneous_charge_reserve_hours;
    kpi.simultaneous_discharge_reserve_hours = simultaneous_discharge_reserve_hours;

    % Power summaries
    kpi.peak_charge_power_kw = peak_charge_power_kw;
    kpi.peak_discharge_power_kw = peak_discharge_power_kw;
    kpi.avg_charge_power_when_active_kw = avg_charge_power_when_active_kw;
    kpi.avg_discharge_power_when_active_kw = avg_discharge_power_when_active_kw;

    % Reserve summaries
    kpi.avg_reserved_capacity_kw = avg_reserved_capacity_kw;
    kpi.max_reserved_capacity_kw = max_reserved_capacity_kw;
    kpi.avg_reserved_capacity_when_active_kw = avg_reserved_capacity_when_active_kw;
    kpi.total_reserved_capacity_kwh_equiv = total_reserved_capacity_kwh_equiv;
    kpi.total_reserved_capacity_mwh_equiv = total_reserved_capacity_mwh_equiv;
    kpi.avg_reserved_fraction_of_power_cap = avg_reserved_fraction_of_power_cap;
    kpi.max_reserved_fraction_of_power_cap = max_reserved_fraction_of_power_cap;

    % Cycling / utilisation
    kpi.equivalent_full_cycles = equivalent_full_cycles;
    kpi.equivalent_cycles_discharge_based = equivalent_cycles_discharge_based;

    % Economic intensity
    kpi.revenue_per_throughput_gbp_per_kwh = revenue_per_throughput_gbp_per_kwh;
    kpi.arbitrage_revenue_per_discharge_gbp_per_kwh = arbitrage_revenue_per_discharge_gbp_per_kwh;
    kpi.ancillary_revenue_per_reserved_mw_h = ancillary_revenue_per_reserved_mw_h;

    % Revenue shares
    kpi.arbitrage_revenue_share = arbitrage_revenue_share;
    kpi.ancillary_revenue_share = ancillary_revenue_share;

    % Price-response summaries
    kpi.avg_price_all_gbp_per_kwh = avg_price_all_gbp_per_kwh;
    kpi.avg_charge_price_gbp_per_kwh = avg_charge_price_gbp_per_kwh;
    kpi.avg_discharge_price_gbp_per_kwh = avg_discharge_price_gbp_per_kwh;
    kpi.avg_ancillary_price_gbp_per_mw_h = avg_ancillary_price_gbp_per_mw_h;
    kpi.avg_ancillary_price_when_reserved_gbp_per_mw_h = ...
        avg_ancillary_price_when_reserved_gbp_per_mw_h;

    % Market-energy summaries
    kpi.net_grid_energy_bought_kwh = net_grid_energy_bought_kwh;
    kpi.net_grid_energy_sold_kwh = net_grid_energy_sold_kwh;
    kpi.net_export_minus_import_kwh = net_export_minus_import_kwh;

    % Time-series values
    kpi.charge_energy_each_step_kwh = charge_energy_each_step_kwh;
    kpi.discharge_energy_each_step_kwh = discharge_energy_each_step_kwh;
    kpi.reserve_capacity_each_step_kw = reserve_capacity_each_step_kw;
    kpi.reserve_capacity_each_step_mw = reserve_capacity_each_step_mw;

    kpi.arbitrage_revenue_each_step_gbp = arbitrage_revenue_each_step_gbp;
    kpi.ancillary_revenue_each_step_gbp = ancillary_revenue_each_step_gbp;
    kpi.total_revenue_each_step_gbp = ...
        arbitrage_revenue_each_step_gbp + ancillary_revenue_each_step_gbp;

    kpi.soc_pct = soc_pct;

    %% 14. Print summary
    fprintf('\n--- Stacking KPI summary ---\n');
    fprintf('Total stacked revenue                 : %.6f GBP\n', kpi.total_revenue_gbp);
    fprintf('Recomputed total revenue              : %.6f GBP\n', kpi.total_revenue_gbp_recomputed);
    fprintf('  Arbitrage revenue                   : %.6f GBP\n', kpi.arbitrage_revenue_gbp);
    fprintf('  Ancillary revenue                   : %.6f GBP\n', kpi.ancillary_revenue_gbp);

    fprintf('Total charge energy                   : %.6f kWh\n', kpi.total_charge_kwh);
    fprintf('Total discharge energy                : %.6f kWh\n', kpi.total_discharge_kwh);
    fprintf('Energy throughput                     : %.6f kWh\n', kpi.energy_throughput_kwh);

    fprintf('SOC min / mean / max                  : %.6f / %.6f / %.6f kWh\n', ...
        kpi.soc_min_kwh, kpi.soc_mean_kwh, kpi.soc_max_kwh);
    fprintf('Initial / final SOC                   : %.6f / %.6f kWh\n', ...
        kpi.soc_initial_kwh_from_solution, kpi.soc_final_kwh);

    fprintf('Charge / discharge / reserve hrs      : %d / %d / %d\n', ...
        kpi.charge_hours, kpi.discharge_hours, kpi.reserve_active_hours);

    fprintf('Average / max reserved capacity       : %.6f / %.6f kW\n', ...
        kpi.avg_reserved_capacity_kw, kpi.max_reserved_capacity_kw);

    fprintf('Equivalent full cycles                : %.6f\n', kpi.equivalent_full_cycles);
    fprintf('Ancillary revenue share               : %.6f\n', kpi.ancillary_revenue_share);

    if ~isnan(kpi.avg_charge_price_gbp_per_kwh)
        fprintf('Avg charge price                      : %.6f GBP/kWh\n', ...
            kpi.avg_charge_price_gbp_per_kwh);
    else
        fprintf('Avg charge price                      : N/A\n');
    end

    if ~isnan(kpi.avg_discharge_price_gbp_per_kwh)
        fprintf('Avg discharge price                   : %.6f GBP/kWh\n', ...
            kpi.avg_discharge_price_gbp_per_kwh);
    else
        fprintf('Avg discharge price                   : N/A\n');
    end

    if ~isnan(kpi.avg_ancillary_price_when_reserved_gbp_per_mw_h)
        fprintf('Avg ancillary price when reserved     : %.6f GBP/MW/h\n', ...
            kpi.avg_ancillary_price_when_reserved_gbp_per_mw_h);
    else
        fprintf('Avg ancillary price when reserved     : N/A\n');
    end

    fprintf('-----------------------------\n\n');
end