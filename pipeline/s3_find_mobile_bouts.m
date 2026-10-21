function results = s3_find_mobile_bouts(action, only)
% Whole-body COP trace and candidate walking bouts ("extract"), manual
% keep/trim GUI ("correct"), per-bout stats ("stats") and the final walking
% windows ("export"). "review_new"/"export_new" do the same with an
% automatic bout detector (detect_walking_bouts), which was not used in the paper's analysis.

if nargin < 1 || strlength(string(action)) == 0
    action = "extract_and_stats";
end
action = lower(string(action));

if nargin < 2, only = []; end
cfg = gait_config();
S = cop_settings();
out_root = cfg.cop_root;
ensure_dir(out_root);

switch action
    case {"extract", "extract_and_stats", "all"}
        raw = extract_all_recordings(cfg, S, out_root, only);
        if action == "extract"
            results = raw;
            return;
        end
    otherwise
        raw_path = fullfile(out_root, 'cop_trajectory_raw.mat');
        if ~exist(raw_path, 'file')
            error('Raw COP results missing. Run s3_find_mobile_bouts("extract") first.');
        end
        loaded = load(raw_path, 'raw_results');
        raw = loaded.raw_results;
end

if action == "export"
    results = export_curated_windows(cfg, out_root);
    return;
end

if action == "review_new" || action == "export_new"
    review_root = fullfile(cfg.cop_root, 'walking_bout_review');
    ensure_dir(review_root);
    raw = use_new_detector_bouts(raw, review_root);
    if action == "review_new"
        launch_correction_gui(raw, review_root, fullfile(review_root, 'cop_trajectory_corrections.csv'));
    else
        export_reviewed_windows(raw, cfg.cop_root, review_root);
    end
    results = raw;
    return;
end

if action == "correct" || action == "all"
    launch_correction_gui(raw, out_root, cfg.bout_corrections_path);
    if action == "correct"
        results = raw;
        return;
    end
end

if action == "stats" || action == "extract_and_stats" || action == "all"
    results = compute_and_save_stats(raw, cfg, out_root);
else
    error('Unknown action: %s', action);
end
end

function T = export_curated_windows(cfg, out_root)
% Kept, trimmed bouts -> mobile_bout_windows.csv (needs "extract" and "stats").
B = readtable(fullfile(out_root, 'cop_tortuosity_by_bout.csv'), 'TextType', 'string', ...
    'VariableNamingRule', 'preserve');
R = load(fullfile(out_root, 'cop_trajectory_raw.mat'), 'raw_results');
rr = R.raw_results;
names = string({rr.output_name});
B = B(B.keep == 1, :);
rec = strings(0, 1); bidx = zeros(0, 1); t0 = zeros(0, 1); t1 = zeros(0, 1);
for k = 1:height(B)
    i = find(names == B.output_name(k), 1);
    if isempty(i), continue; end
    s = B.trim_start_idx(k); e = B.trim_end_idx(k);
    if s < 1 || e > numel(rr(i).t) || e <= s, continue; end
    rec(end+1, 1) = B.output_name(k); %#ok<AGROW>
    bidx(end+1, 1) = B.bout_index(k); %#ok<AGROW>
    t0(end+1, 1) = rr(i).t(s); %#ok<AGROW>
    t1(end+1, 1) = rr(i).t(e); %#ok<AGROW>
end
T = sortrows(table(rec, bidx, t0, t1, 'VariableNames', {'recording', 'bout_index', 't_start', 't_end'}), ...
    {'recording', 't_start'});
out = fullfile(out_root, 'mobile_bout_windows.csv');
writetable(T, out);
fprintf('Wrote %d kept mobile bouts for %d recordings (%.0f s total) to %s\n', ...
    height(T), numel(unique(T.recording)), sum(T.t_end - T.t_start), out);
end

function raw = use_new_detector_bouts(raw, review_root)
% Swap in cached detect_walking_bouts candidates (review preset) for the GUI.
cache_path = fullfile(review_root, 'detector_candidates.csv');
use_cache = exist(cache_path, 'file') == 2;
if ~use_cache
    saved = read_corrections(fullfile(review_root, 'cop_trajectory_corrections.csv'));
    if height(saved) > 0
        error(['%s is missing but %d review decision(s) are saved; rebuilding the ' ...
            'candidates would renumber the bouts under them. Restore the cache, or ' ...
            'move cop_trajectory_corrections.csv aside to start a fresh review.'], ...
            cache_path, height(saved));
    end
end
if use_cache
    C = readtable(cache_path, 'TextType', 'string', 'Delimiter', ',', ...
        'VariableNamingRule', 'preserve');
    fprintf('Using cached candidates: %s (delete it to recompute).\n', cache_path);
end
rows = {};
for i = 1:numel(raw)
    rec = string(raw(i).output_name);
    t = raw(i).t(:);
    cop = struct('t', t, 'cop_x_mm', raw(i).cop_x_mm, 'cop_y_mm', raw(i).cop_y_mm, ...
        'total_pressure', raw(i).total_pressure);
    [B, info] = detect_walking_bouts(cop, [], struct('preset', 'review'));
    if use_cache
        Ci = sortrows(C(C.output_name == rec, :), 'bout_index');
        B = [Ci.t_start, Ci.t_end];
    else
        for b = 1:size(B, 1)
            rows(end+1, :) = {rec, b, B(b, 1), B(b, 2)}; %#ok<AGROW>
        end
    end
    s = zeros(size(B, 1), 1); e = s;
    for b = 1:size(B, 1)
        s(b) = find(t >= B(b, 1) - 1e-9, 1, 'first');
        e(b) = find(t <= B(b, 2) + 1e-9, 1, 'last');
    end
    raw(i).bout_starts = s;
    raw(i).bout_ends = e;
    raw(i).n_bouts = numel(s);
    raw(i).velocity_mm_s = abs(info.velocity_x_mm_s(:));
end
if ~use_cache
    C = cell2table(rows, 'VariableNames', {'output_name', 'bout_index', 't_start', 't_end'});
    writetable(C, cache_path);
end
fprintf('%d candidate bouts in %d recordings.\n', sum([raw.n_bouts]), numel(raw));
end

function export_reviewed_windows(raw, script_dir, review_root)
% Saved decisions from "review_new" -> mobile_bout_windows_reviewed.csv.
corrections = read_corrections(fullfile(review_root, 'cop_trajectory_corrections.csv'));
rec = strings(0, 1); bidx = zeros(0, 1); t0 = zeros(0, 1); t1 = zeros(0, 1);
n_total = 0; n_unreviewed = 0;
for i = 1:numel(raw)
    for b = 1:numel(raw(i).bout_starts)
        n_total = n_total + 1;
        corr = find_correction(raw(i).output_name, b, corrections);
        if isempty(corr), n_unreviewed = n_unreviewed + 1; continue; end
        if corr.original_start_idx ~= raw(i).bout_starts(b) || corr.original_end_idx ~= raw(i).bout_ends(b)
            warning('%s bout %d: saved correction does not match the current candidate; skipped.', ...
                raw(i).output_name, b);
            continue;
        end
        if ~corr.keep, continue; end
        rec(end+1, 1) = string(raw(i).output_name); %#ok<AGROW>
        bidx(end+1, 1) = b; %#ok<AGROW>
        t0(end+1, 1) = raw(i).t(corr.trim_start_idx); %#ok<AGROW>
        t1(end+1, 1) = raw(i).t(corr.trim_end_idx); %#ok<AGROW>
    end
end
T = sortrows(table(rec, bidx, t0, t1, 'VariableNames', {'recording', 'bout_index', 't_start', 't_end'}), ...
    {'recording', 't_start'});
out = fullfile(script_dir, 'mobile_bout_windows_reviewed.csv');
writetable(T, out);
fprintf('Wrote %d kept windows (%.0f s) to %s; %d of %d candidates not reviewed yet.\n', ...
    height(T), sum(T.t_end - T.t_start), out, n_unreviewed, n_total);
end

function S = cop_settings()
S.BOARD_SIZE = 64;
S.MAX_BOARD_ID = 4;
S.LAYOUT_BOARD_IDS = [4 3 2 1];
S.TRANSFORMS_BY_ID = {'none', 'none', 'none', 'none'};
S.GRID_ROWS = 1;
S.GRID_COLS = 4;
S.PIXEL_SIZE_MM = 2.0;
S.PRESSURE_THRES = 700;
S.MIN_TOTAL_PRESSURE = S.PRESSURE_THRES * 150;
S.TARGET_FS = 100;
S.MEDFILT_WIN = 10;
S.LOWPASS_HZ = 3.0;
S.MIN_BOUT_SEC = 2.0;
S.MERGE_GAP_SEC = 1.0;
S.VEL_WINDOW_SEC = 3.0;
S.STAT_QUANTILE = 0.35;
S.UP_QUANTILE = 0.60;
S.DOWN_QUANTILE = 0.40;
S.MIN_CONSEC_SEC = 0.05;
S.MIN_DUR_SEC = 0.30;
S.IGNORE_FIRST_SEC = 5.0;
S.MIN_VALID_POINTS = 10;
S.MIN_DISPLACEMENT_MM = 10.0;
S.BODY_BG_DIFF_THRESH = 100;
S.BODY_MIN_BLOB_AREA = 27903;
S.BODY_CLOSE_RADIUS = 4;
S.BODY_OPEN_RADIUS = 3;
end

function raw_results = extract_all_recordings(cfg, S, out_root, only)
[~, recordings] = gait_config(only);
raw_results = repmat(empty_recording_result(), 0, 1);

fprintf('Extracting timestamp-synced COP trajectories from %d recording row(s)...\n', ...
    height(recordings));
for i = 1:height(recordings)
    input_file = string(recordings.input_file(i));
    output_name = string(recordings.output_name(i));
    if ~exist(input_file, 'file')
        warning('Missing tactile file: %s', input_file);
        continue;
    end

    meta = parse_recording_metadata(output_name, cfg.surgery_date);
    fprintf('  %s ... ', output_name);
    try
        raw = extract_cop_and_bouts(input_file, S);
        raw.recording_date = meta.recording_date;
        raw.days_from_surgery = meta.days_from_surgery;
        raw.rat = meta.rat;
        raw.group = meta.group;
        raw.surgery_phase = meta.surgery_phase;
        raw.output_name = output_name;
        raw.input_file = input_file;
        raw.n_bouts = numel(raw.bout_starts);
        raw_results(end+1, 1) = raw; %#ok<AGROW>
        fprintf('%d mobile bout(s)\n', raw.n_bouts);
    catch ME
        warning('%s failed: %s', output_name, ME.message);
        fprintf('failed\n');
    end
end

raw_path = fullfile(out_root, 'cop_trajectory_raw.mat');
save(raw_path, 'raw_results', 'S', '-v7.3');
writetable(raw_recording_table(raw_results), fullfile(out_root, ...
    'cop_trajectory_recording_inventory.csv'));
fprintf('Saved raw COP trajectories: %s\n', raw_path);
end

function raw = extract_cop_and_bouts(mat_path, S)
tac = load(mat_path);
[board_names, board_ts, t_raw] = prepare_board_timestamps(tac, S);
dt = median(diff(t_raw), 'omitnan');
fs_orig = 1 / dt;
ds_factor = max(1, round(fs_orig / S.TARGET_FS));
fs_ds = fs_orig / ds_factor;
t_ds = t_raw(1:ds_factor:end);
n_ds = numel(t_ds);

cop_x = nan(n_ds, 1);
cop_y = nan(n_ds, 1);
geom_x = nan(n_ds, 1);
geom_y = nan(n_ds, 1);
total_pressure = zeros(n_ds, 1);
n_active_px = zeros(n_ds, 1);

for i = 1:n_ds
    frame = render_frame_timestamp_synced(tac, board_names, board_ts, ...
        t_ds(i), S);
    mask = frame > S.PRESSURE_THRES;
    [rr, cc] = find(mask);
    if numel(rr) < 2
        continue;
    end
    vals = frame(mask);
    w = sum(vals, 'omitnan');
    if w <= 0
        continue;
    end
    cop_x(i) = sum(double(cc) .* double(vals)) / w * S.PIXEL_SIZE_MM;
    cop_y(i) = sum(double(rr) .* double(vals)) / w * S.PIXEL_SIZE_MM;
    geom_x(i) = mean(double(cc), 'omitnan') * S.PIXEL_SIZE_MM;
    geom_y(i) = mean(double(rr), 'omitnan') * S.PIXEL_SIZE_MM;
    total_pressure(i) = w;
    n_active_px(i) = numel(vals);
end

[cop_xf, cop_yf] = smooth_cop(cop_x, cop_y, fs_ds, S);
[geom_xf, geom_yf] = smooth_cop(geom_x, geom_y, fs_ds, S);
[is_moving, velocity] = detect_mobile_state(cop_xf, cop_yf, total_pressure, ...
    t_ds, fs_ds, S);
[~, geom_velocity] = detect_mobile_state(geom_xf, geom_yf, total_pressure, ...
    t_ds, fs_ds, S);
tr = diff([false; is_moving(:); false]);

raw = empty_recording_result();
raw.t = t_ds(:) - t_ds(1);
raw.source_t = t_ds(:);
raw.cop_x_mm = cop_xf(:);
raw.cop_y_mm = cop_yf(:);
raw.raw_cop_x_mm = cop_x(:);
raw.raw_cop_y_mm = cop_y(:);
raw.geom_centroid_x_mm = geom_xf(:);
raw.geom_centroid_y_mm = geom_yf(:);
raw.raw_geom_centroid_x_mm = geom_x(:);
raw.raw_geom_centroid_y_mm = geom_y(:);
raw.total_pressure = total_pressure(:);
raw.n_active_px = n_active_px(:);
raw.velocity_mm_s = velocity(:);
raw.geom_centroid_velocity_mm_s = geom_velocity(:);
raw.is_moving = is_moving(:);
raw.bout_starts = find(tr == 1);
raw.bout_ends = find(tr == -1) - 1;
raw.fs = fs_ds;
end

function [cop_xf, cop_yf] = smooth_cop(cop_x, cop_y, fs_ds, S)
cop_xf = cop_x;
cop_yf = cop_y;
ok = ~isnan(cop_x) & ~isnan(cop_y);
if sum(ok) <= S.MEDFILT_WIN
    return;
end
xi = (1:numel(cop_x))';
cop_xf(~ok) = interp1(xi(ok), cop_x(ok), xi(~ok), 'nearest', 'extrap');
cop_yf(~ok) = interp1(xi(ok), cop_y(ok), xi(~ok), 'nearest', 'extrap');
cop_xf = medfilt1(cop_xf, S.MEDFILT_WIN);
cop_yf = medfilt1(cop_yf, S.MEDFILT_WIN);
if S.LOWPASS_HZ < fs_ds / 2
    [b, a] = butter(4, S.LOWPASS_HZ / (fs_ds / 2), 'low');
    cop_xf = filtfilt(b, a, cop_xf);
    cop_yf = filtfilt(b, a, cop_yf);
end
cop_xf(~ok) = NaN;
cop_yf(~ok) = NaN;
end

function [is_moving, velocity] = detect_mobile_state(cop_x, cop_y, ...
    total_pressure, t, fs_ds, S)
n = numel(t);
velocity = zeros(n, 1);
vel_step = max(1, round(S.VEL_WINDOW_SEC * fs_ds / 2));
for i = vel_step+1:n-vel_step
    dx = cop_x(i+vel_step) - cop_x(i-vel_step);
    dy = cop_y(i+vel_step) - cop_y(i-vel_step);
    dt = t(i+vel_step) - t(i-vel_step);
    if dt > 0
        velocity(i) = hypot(dx, dy) / dt;
    end
end

speed = movmean(abs(velocity), max(3, round(0.10 * fs_ds)), 'omitnan');
nz = speed(speed > 0 & ~isnan(speed));
if isempty(nz)
    is_moving = false(n, 1);
    return;
end

stationary_thresh = quantile(nz, S.STAT_QUANTILE);
candidate_speed = nz(nz >= stationary_thresh);
if isempty(candidate_speed)
    move_thresh = stationary_thresh;
else
    move_thresh = quantile(candidate_speed, S.UP_QUANTILE);
end

is_moving_raw = speed >= move_thresh & total_pressure(:) > S.MIN_TOTAL_PRESSURE;
is_moving_raw(t(:) - t(1) < S.IGNORE_FIRST_SEC) = false;
min_consec = max(1, round(S.MIN_CONSEC_SEC * fs_ds));
min_dur = max(1, round(S.MIN_DUR_SEC * fs_ds));
raw = medfilt1(double(is_moving_raw), 5) > 0.5;
raw = movsum(double(raw), [min_consec-1 0]) >= min_consec;
raw = bwareaopen(logical(raw), min_dur);

close_frames = max(1, round(S.MERGE_GAP_SEC * fs_ds));
is_moving = imclose(raw(:), ones(close_frames, 1));
is_moving = bwareaopen(is_moving, max(1, round(S.MIN_BOUT_SEC * fs_ds)));
end

function [board_names, board_ts, t_raw] = prepare_board_timestamps(tac, S)
board_names = {};
for id = 1:S.MAX_BOARD_ID
    name = sprintf('Board%d', id);
    if isfield(tac, [name '_timestamps'])
        board_names{end+1} = name; %#ok<AGROW>
    end
end
if isempty(board_names)
    error('No BoardN timestamp fields found.');
end

board_ts = cell(1, S.MAX_BOARD_ID);
t_raw = [];
for i = 1:numel(board_names)
    name = board_names{i};
    ts = tac.([name '_timestamps']);
    if iscell(ts), ts = cell2mat(ts); end
    ts = double(ts(:));
    id = board_id_for_name_or_data(tac, name, S);
    if id >= 1 && id <= S.MAX_BOARD_ID
        board_ts{id} = ts;
    end
    if isempty(t_raw)
        t_raw = ts;
    end
end
if isempty(t_raw) || numel(t_raw) < 2
    error('Master timestamp vector is empty or too short.');
end
end

function frame = render_frame_timestamp_synced(tac, board_names, board_ts, ...
    t_query, S)
boards = cell(1, S.MAX_BOARD_ID);
for id = 1:S.MAX_BOARD_ID
    boards{id} = zeros(S.BOARD_SIZE);
end

for i = 1:numel(board_names)
    name = board_names{i};
    id = board_id_for_name_or_data(tac, name, S);
    if id < 1 || id > S.MAX_BOARD_ID || isempty(board_ts{id})
        continue;
    end
    [~, frame_idx] = min(abs(board_ts{id} - t_query));
    img = render_board_frame(tac, name, frame_idx, S);
    boards{id} = apply_transform(img, S.TRANSFORMS_BY_ID{id});
end

frame = zeros(S.BOARD_SIZE * S.GRID_ROWS, S.BOARD_SIZE * S.GRID_COLS);
for pos = 1:numel(S.LAYOUT_BOARD_IDS)
    id = S.LAYOUT_BOARD_IDS(pos);
    if id < 1 || id > S.MAX_BOARD_ID
        continue;
    end
    gr = floor((pos - 1) / S.GRID_COLS);
    gc = mod(pos - 1, S.GRID_COLS);
    rows = gr * S.BOARD_SIZE + (1:S.BOARD_SIZE);
    cols = gc * S.BOARD_SIZE + (1:S.BOARD_SIZE);
    frame(rows, cols) = boards{id};
end
frame(frame < S.PRESSURE_THRES) = 0;
end

function img = render_board_frame(tac, name, frame_idx, S)
img = zeros(S.BOARD_SIZE);
idx_field = [name '_pixel_indices'];
val_field = [name '_pixel_values'];
if ~isfield(tac, idx_field) || ~isfield(tac, val_field)
    return;
end

indices = tac.(idx_field);
values = tac.(val_field);
if iscell(indices)
    frame_idx = min(frame_idx, numel(indices));
    idx = indices{frame_idx};
    vals = values{frame_idx};
elseif isnumeric(indices)
    frame_idx = min(frame_idx, size(indices, 1));
    idx = indices(frame_idx, :);
    vals = values(frame_idx, :);
    keep = idx ~= 0;
    idx = idx(keep);
    vals = vals(keep);
else
    return;
end

for j = 1:numel(idx)
    [r, c] = pressure_index_to_coords(idx(j));
    if r >= 1 && r <= S.BOARD_SIZE && c >= 1 && c <= S.BOARD_SIZE
        img(r, c) = vals(j);
    end
end
end

function launch_correction_gui(raw_results, out_root, correction_path)
corrections = read_corrections(correction_path);
state.raw = raw_results;
state.out_root = out_root;
state.correction_path = correction_path;
state.corrections = corrections;
state.current_recording = 1;
state.current_bout = 1;

fig = figure('Name', 'Walking-bout review', ...
    'NumberTitle', 'off', 'Color', 'w', 'Position', [80 80 1320 760], ...
    'CloseRequestFcn', @on_close);
ui.rec_list = uicontrol(fig, 'Style', 'listbox', 'Units', 'normalized', ...
    'Position', [0.02 0.12 0.23 0.84], 'FontSize', 9, ...
    'Callback', @on_recording_change);
ui.bout_list = uicontrol(fig, 'Style', 'listbox', 'Units', 'normalized', ...
    'Position', [0.27 0.12 0.16 0.84], 'FontSize', 9, ...
    'Callback', @on_bout_change);
ui.ax_traj = axes(fig, 'Units', 'normalized', 'Position', [0.48 0.45 0.48 0.47]);
ui.ax_vel = axes(fig, 'Units', 'normalized', 'Position', [0.48 0.24 0.48 0.14]);
ui.trim_start = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.48 0.17 0.22 0.035], 'Callback', @on_trim);
ui.trim_end = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.74 0.17 0.22 0.035], 'Callback', @on_trim);
ui.keep = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Keep', ...
    'Units', 'normalized', 'Position', [0.48 0.08 0.10 0.055], ...
    'Value', 1, 'Callback', @on_keep);
ui.reject = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Reject', ...
    'Units', 'normalized', 'Position', [0.60 0.08 0.10 0.055], ...
    'Value', 0, 'Callback', @on_reject);
ui.save_next = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Save + Next', ...
    'Units', 'normalized', 'Position', [0.72 0.08 0.12 0.055], ...
    'Callback', @on_save_next);
ui.status = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.02 0.02 0.94 0.055], 'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w', 'FontSize', 10);

refresh_recording_list();
refresh_bout_list();
refresh_detail();
uiwait(fig);

    function refresh_recording_list()
        labels = strings(numel(state.raw), 1);
        for i = 1:numel(state.raw)
            n_done = count_corrected_bouts(state.raw(i).output_name, ...
                state.corrections);
            labels(i) = sprintf('%s | %d bout(s), %d corrected', ...
                state.raw(i).output_name, numel(state.raw(i).bout_starts), n_done);
        end
        set(ui.rec_list, 'String', cellstr(labels), ...
            'Value', min(state.current_recording, max(1, numel(labels))));
    end

    function refresh_bout_list()
        raw = state.raw(state.current_recording);
        labels = strings(numel(raw.bout_starts), 1);
        for b = 1:numel(raw.bout_starts)
            corr = find_correction(raw.output_name, b, state.corrections);
            tag = "uncorrected";
            if ~isempty(corr)
                if corr.keep
                    tag = "kept";
                else
                    tag = "rejected";
                end
            end
            labels(b) = sprintf('Bout %d | %.2f-%.2f s | %s', b, ...
                raw.t(raw.bout_starts(b)), raw.t(raw.bout_ends(b)), tag);
        end
        if isempty(labels), labels = "No bouts"; end
        set(ui.bout_list, 'String', cellstr(labels), ...
            'Value', min(state.current_bout, max(1, numel(labels))));
    end

    function refresh_detail()
        raw = state.raw(state.current_recording);
        if isempty(raw.bout_starts)
            cla(ui.ax_traj); cla(ui.ax_vel);
            set(ui.status, 'String', 'No mobile bouts for this recording.');
            return;
        end
        b = state.current_bout;
        i0 = raw.bout_starts(b);
        i1 = raw.bout_ends(b);
        corr = find_correction(raw.output_name, b, state.corrections);
        if isempty(corr)
            trim_start = i0;
            trim_end = i1;
            keep = true;
        else
            trim_start = max(i0, min(i1, corr.trim_start_idx));
            trim_end = max(trim_start, min(i1, corr.trim_end_idx));
            keep = corr.keep;
        end
        configure_slider(ui.trim_start, i0, i1, trim_start);
        configure_slider(ui.trim_end, i0, i1, trim_end);
        set(ui.keep, 'Value', keep);
        set(ui.reject, 'Value', ~keep);
        plot_current_bout(raw, b, trim_start, trim_end, ui);
    end

    function on_recording_change(~, ~)
        state.current_recording = get(ui.rec_list, 'Value');
        state.current_bout = 1;
        refresh_bout_list();
        refresh_detail();
    end

    function on_bout_change(~, ~)
        state.current_bout = get(ui.bout_list, 'Value');
        refresh_detail();
    end

    function on_trim(~, ~)
        lo = round(get(ui.trim_start, 'Value'));
        hi = round(get(ui.trim_end, 'Value'));
        if lo >= hi
            hi = lo + 1;
            set(ui.trim_end, 'Value', hi);
        end
        raw = state.raw(state.current_recording);
        plot_current_bout(raw, state.current_bout, lo, hi, ui);
    end

    function on_keep(~, ~)
        set(ui.keep, 'Value', 1);
        set(ui.reject, 'Value', 0);
    end

    function on_reject(~, ~)
        set(ui.keep, 'Value', 0);
        set(ui.reject, 'Value', 1);
    end

    function on_save_next(~, ~)
        save_current_correction();
        raw = state.raw(state.current_recording);
        if state.current_bout < numel(raw.bout_starts)
            state.current_bout = state.current_bout + 1;
        elseif state.current_recording < numel(state.raw)
            state.current_recording = state.current_recording + 1;
            state.current_bout = 1;
        end
        refresh_recording_list();
        refresh_bout_list();
        refresh_detail();
    end

    function save_current_correction()
        raw = state.raw(state.current_recording);
        b = state.current_bout;
        if isempty(raw.bout_starts) || b > numel(raw.bout_starts)
            return;
        end
        row = table();
        row.timestamp = datetime("now");
        row.output_name = string(raw.output_name);
        row.rat = raw.rat;
        row.recording_date = raw.recording_date;
        row.bout_index = b;
        row.original_start_idx = raw.bout_starts(b);
        row.original_end_idx = raw.bout_ends(b);
        row.trim_start_idx = round(get(ui.trim_start, 'Value'));
        row.trim_end_idx = round(get(ui.trim_end, 'Value'));
        row.keep = logical(get(ui.keep, 'Value'));
        state.corrections = upsert_correction(state.corrections, row);
        writetable(state.corrections, state.correction_path);
        set(ui.status, 'String', sprintf('Saved correction: %s bout %d', ...
            raw.output_name, b));
    end

    function on_close(~, ~)
        try
            writetable(state.corrections, state.correction_path);
        catch
        end
        uiresume(fig);
        delete(fig);
    end
end

function plot_current_bout(raw, b, trim_start, trim_end, ui)
i0 = raw.bout_starts(b);
i1 = raw.bout_ends(b);
idx = i0:i1;
trim_idx = trim_start:trim_end;
cla(ui.ax_traj);
plot(ui.ax_traj, raw.cop_x_mm(idx), raw.cop_y_mm(idx), '-', ...
    'Color', [0.70 0.70 0.70], 'LineWidth', 1.0);
hold(ui.ax_traj, 'on');
plot(ui.ax_traj, raw.cop_x_mm(trim_idx), raw.cop_y_mm(trim_idx), 'r-', ...
    'LineWidth', 2.0);
plot(ui.ax_traj, raw.cop_x_mm(trim_start), raw.cop_y_mm(trim_start), ...
    'go', 'MarkerFaceColor', 'g');
plot(ui.ax_traj, raw.cop_x_mm(trim_end), raw.cop_y_mm(trim_end), ...
    'ko', 'MarkerFaceColor', 'k');
hold(ui.ax_traj, 'off');
axis(ui.ax_traj, 'equal');
grid(ui.ax_traj, 'on');
xlabel(ui.ax_traj, 'COP x (mm)');
ylabel(ui.ax_traj, 'COP y (mm)');
title(ui.ax_traj, sprintf('%s | Bout %d | TI %.3f', raw.output_name, b, ...
    compute_tortuosity(raw, trim_start, trim_end)));

cla(ui.ax_vel);
plot(ui.ax_vel, raw.t(idx), raw.velocity_mm_s(idx), 'k-', 'LineWidth', 1.0);
hold(ui.ax_vel, 'on');
xline(ui.ax_vel, raw.t(trim_start), 'g-', 'LineWidth', 1.2);
xline(ui.ax_vel, raw.t(trim_end), 'r-', 'LineWidth', 1.2);
hold(ui.ax_vel, 'off');
grid(ui.ax_vel, 'on');
xlabel(ui.ax_vel, 'Time (s)');
ylabel(ui.ax_vel, 'Speed (mm/s)');
end

function results = compute_and_save_stats(raw_results, cfg, out_root)
surgery_date = cfg.surgery_date;
S = cop_settings();
[~, recordings] = gait_config();
corrections = read_corrections(cfg.bout_corrections_path);
bout_rows = {};
for i = 1:numel(raw_results)
    raw = raw_results(i);
    video_ctx = [];
    for b = 1:numel(raw.bout_starts)
        corr = find_correction(raw.output_name, b, corrections);
        if isempty(corr)
            keep = true;
            trim_start = raw.bout_starts(b);
            trim_end = raw.bout_ends(b);
        else
            keep = corr.keep;
            trim_start = corr.trim_start_idx;
            trim_end = corr.trim_end_idx;
        end
        stats = bout_stats(raw, trim_start, trim_end);
        geom_stats = empty_path_stats();
        if keep
            try
                if isempty(video_ctx)
                    video_ctx = open_video_centroid_context(recordings, raw.output_name, S);
                end
                geom_stats = video_body_centroid_bout_stats(video_ctx, ...
                    raw, trim_start, trim_end, S);
            catch ME
                warning('Video body centroid failed for %s bout %d: %s', ...
                    raw.output_name, b, ME.message);
            end
        end
        bout_rows(end+1, :) = { ... %#ok<AGROW>
            raw.recording_date, raw.days_from_surgery, epoch_for_days(raw.days_from_surgery), ...
            raw.rat, raw.group, raw.surgery_phase, raw.output_name, b, ...
            keep, trim_start, trim_end, stats.duration_s, stats.n_points, ...
            stats.path_length_mm, stats.displacement_mm, stats.tortuosity, ...
            stats.higuchi_fd, stats.higuchi_kmax, ...
            stats.mean_speed_mm_s, stats.net_speed_mm_s, ...
            geom_stats.path_length_mm, geom_stats.displacement_mm, ...
            geom_stats.mean_speed_mm_s, geom_stats.net_speed_mm_s};
    end
end

var_names = {'recording_date', 'days_from_surgery', 'epoch', 'rat', ...
    'group', 'surgery_phase', 'output_name', 'bout_index', 'keep', ...
    'trim_start_idx', 'trim_end_idx', 'duration_s', 'n_points', ...
    'path_length_mm', 'displacement_mm', 'tortuosity', ...
    'higuchi_fd', 'higuchi_kmax', 'mean_speed_mm_s', 'net_speed_mm_s', ...
    'geom_centroid_path_length_mm', 'geom_centroid_displacement_mm', ...
    'geom_centroid_mean_speed_mm_s', 'geom_centroid_net_speed_mm_s'};
if isempty(bout_rows)
    bout_table = cell2table(cell(0, numel(var_names)), ...
        'VariableNames', var_names);
else
    bout_table = cell2table(bout_rows, 'VariableNames', var_names);
end

valid = bout_table.keep & ~isnan(bout_table.tortuosity);
recording_table = summarize_bouts(bout_table(valid, :), ...
    ["recording_date", "days_from_surgery", "epoch", "rat", "group", ...
    "surgery_phase", "output_name"]);
epoch_table = summarize_bouts(bout_table(valid, :), ["epoch", "rat", "group"]);

writetable(bout_table, fullfile(out_root, 'cop_tortuosity_by_bout.csv'));
writetable(recording_table, fullfile(out_root, 'cop_tortuosity_by_recording.csv'));
writetable(epoch_table, fullfile(out_root, 'cop_tortuosity_by_epoch.csv'));
writetable(bout_table, fullfile(out_root, 'cop_higuchi_fd_by_bout.csv'));
writetable(recording_table, fullfile(out_root, 'cop_higuchi_fd_by_recording.csv'));
writetable(epoch_table, fullfile(out_root, 'cop_higuchi_fd_by_epoch.csv'));

results = struct('bout_table', bout_table, 'recording_table', recording_table, ...
    'epoch_table', epoch_table);
fprintf('Saved COP trajectory statistics under: %s\n', out_root);
end

function summary = summarize_bouts(T, group_vars)
if isempty(T)
    summary = table();
    return;
end
[G, summary] = findgroups(T(:, cellstr(group_vars)));
summary.n_bouts = splitapply(@numel, T.tortuosity, G);
summary.mean_tortuosity = splitapply(@mean, T.tortuosity, G);
summary.median_tortuosity = splitapply(@median, T.tortuosity, G);
summary.sem_tortuosity = splitapply(@sem_value, T.tortuosity, G);
summary.mean_higuchi_fd = splitapply(@mean, T.higuchi_fd, G);
summary.median_higuchi_fd = splitapply(@median, T.higuchi_fd, G);
summary.sem_higuchi_fd = splitapply(@sem_value, T.higuchi_fd, G);
summary.mean_duration_s = splitapply(@mean, T.duration_s, G);
summary.mean_path_length_mm = splitapply(@mean, T.path_length_mm, G);
summary.mean_displacement_mm = splitapply(@mean, T.displacement_mm, G);
summary.mean_speed_mm_s = splitapply(@mean, T.mean_speed_mm_s, G);
summary.median_speed_mm_s = splitapply(@median, T.mean_speed_mm_s, G);
summary.sem_speed_mm_s = splitapply(@sem_value, T.mean_speed_mm_s, G);
summary.mean_net_speed_mm_s = splitapply(@mean, T.net_speed_mm_s, G);
if ismember('geom_centroid_mean_speed_mm_s', T.Properties.VariableNames)
    summary.geom_centroid_mean_speed_mm_s = ...
        splitapply(@mean, T.geom_centroid_mean_speed_mm_s, G);
    summary.geom_centroid_median_speed_mm_s = ...
        splitapply(@median, T.geom_centroid_mean_speed_mm_s, G);
    summary.geom_centroid_sem_speed_mm_s = ...
        splitapply(@sem_value, T.geom_centroid_mean_speed_mm_s, G);
    summary.geom_centroid_mean_net_speed_mm_s = ...
        splitapply(@mean, T.geom_centroid_net_speed_mm_s, G);
end
end

function stats = bout_stats(raw, i0, i1, x_field, y_field)
if nargin < 4
    x_field = 'cop_x_mm';
    y_field = 'cop_y_mm';
end
i0 = max(1, min(numel(raw.t), round(i0)));
i1 = max(i0, min(numel(raw.t), round(i1)));
if ~isfield(raw, x_field) || ~isfield(raw, y_field)
    x = nan(i1 - i0 + 1, 1);
    y = nan(i1 - i0 + 1, 1);
else
    x = raw.(x_field)(i0:i1);
    y = raw.(y_field)(i0:i1);
end
t = raw.t(i0:i1);
ok = ~isnan(x) & ~isnan(y) & ~isnan(t);
x = x(ok);
y = y(ok);
t = t(ok);

stats = struct('duration_s', NaN, 'n_points', numel(x), ...
    'path_length_mm', NaN, 'displacement_mm', NaN, 'tortuosity', NaN, ...
    'higuchi_fd', NaN, 'higuchi_kmax', NaN, ...
    'mean_speed_mm_s', NaN, 'net_speed_mm_s', NaN);
if numel(x) < 2
    return;
end
stats.duration_s = t(end) - t(1);
step_lengths = hypot(diff(x), diff(y));
stats.path_length_mm = sum(step_lengths, 'omitnan');
stats.displacement_mm = hypot(x(end) - x(1), y(end) - y(1));
if stats.displacement_mm >= 10
    stats.tortuosity = stats.path_length_mm / stats.displacement_mm;
end
[stats.higuchi_fd, stats.higuchi_kmax] = higuchi_fd_2d(x, y);
if stats.duration_s > 0
    stats.mean_speed_mm_s = stats.path_length_mm / stats.duration_s;
    stats.net_speed_mm_s = stats.displacement_mm / stats.duration_s;
end
end

function stats = empty_path_stats()
stats = struct('duration_s', NaN, 'n_points', 0, ...
    'path_length_mm', NaN, 'displacement_mm', NaN, 'tortuosity', NaN, ...
    'higuchi_fd', NaN, 'higuchi_kmax', NaN, ...
    'mean_speed_mm_s', NaN, 'net_speed_mm_s', NaN);
end

function ctx = open_video_centroid_context(recordings, output_name, S)
row = find(recordings.output_name == string(output_name), 1);
if isempty(row)
    error('No recording-list row found for %s.', output_name);
end

input_file = char(recordings.input_file(row));
video_path = char(recordings.camera1_path(row));
background_path = char(recordings.background_path(row));
homography_path = char(recordings.homography_path(row));

tac = load(input_file, 'camera1_frame_timestamps', 'camera0_frame_timestamps');
if isfield(tac, 'camera1_frame_timestamps')
    camera_ts = double(tac.camera1_frame_timestamps(:));
elseif isfield(tac, 'camera0_frame_timestamps')
    camera_ts = double(tac.camera0_frame_timestamps(:));
else
    error('No camera frame timestamps found in %s.', input_file);
end
camera_ts = camera_ts - camera_ts(1);

bg = load(background_path, 'bg_model', 'frame_transform');
hom = load(homography_path, 'tform');
ctx.video = VideoReader(video_path);
ctx.camera_ts = camera_ts;
ctx.bg_gray = rgb2gray(bg.bg_model);
ctx.frame_transform = bg.frame_transform;
ctx.tform = hom.tform;
ctx.S = S;
ctx.last_camera_idx = NaN;
ctx.last_frame_rot = [];
end

function stats = video_body_centroid_bout_stats(ctx, raw, i0, i1, S)
stats = empty_path_stats();
i0 = max(1, min(numel(raw.t), round(i0)));
i1 = max(i0, min(numel(raw.t), round(i1)));
t0 = raw.t(i0);
t1 = raw.t(i1);
if ~(isfinite(t0) && isfinite(t1)) || t1 <= t0
    return;
end

camera_idx = find(ctx.camera_ts >= t0 & ctx.camera_ts <= t1);
if numel(camera_idx) < 2
    [~, idx0] = min(abs(ctx.camera_ts - t0));
    [~, idx1] = min(abs(ctx.camera_ts - t1));
    camera_idx = unique([idx0; idx1]);
end
camera_idx = camera_idx(:);

x = nan(numel(camera_idx), 1);
y = nan(numel(camera_idx), 1);
t = ctx.camera_ts(camera_idx);
for k = 1:numel(camera_idx)
    [frame_rot, ctx] = read_video_frame_for_centroid(ctx, camera_idx(k));
    mask = video_body_mask(frame_rot, ctx.bg_gray, ctx.tform, S);
    props = regionprops(mask, 'Centroid', 'Area');
    if isempty(props)
        continue;
    end
    [~, largest] = max([props.Area]);
    c = props(largest).Centroid;
    x(k) = c(1) * S.PIXEL_SIZE_MM;
    y(k) = c(2) * S.PIXEL_SIZE_MM;
end

ok = ~isnan(x) & ~isnan(y) & ~isnan(t);
x = x(ok);
y = y(ok);
t = t(ok);
stats.n_points = numel(x);
if numel(x) < 2
    return;
end
stats.duration_s = t(end) - t(1);
step_lengths = hypot(diff(x), diff(y));
stats.path_length_mm = sum(step_lengths, 'omitnan');
stats.displacement_mm = hypot(x(end) - x(1), y(end) - y(1));
if stats.duration_s > 0
    stats.mean_speed_mm_s = stats.path_length_mm / stats.duration_s;
    stats.net_speed_mm_s = stats.displacement_mm / stats.duration_s;
end
end

function [frame_rot, ctx] = read_video_frame_for_centroid(ctx, camera_idx)
if camera_idx == ctx.last_camera_idx && ~isempty(ctx.last_frame_rot)
    frame_rot = ctx.last_frame_rot;
    return;
end

if camera_idx == ctx.last_camera_idx + 1 && hasFrame(ctx.video)
    frame = readFrame(ctx.video);
else
    ctx.video.CurrentTime = max(0, (camera_idx - 1) / ctx.video.FrameRate);
    frame = readFrame(ctx.video);
end
ctx.last_frame_rot = apply_frame_transform(frame, ctx.frame_transform);
ctx.last_camera_idx = camera_idx;
frame_rot = ctx.last_frame_rot;
end

function mask = video_body_mask(frame_rot, bg_gray, tform, S)
diff_img = abs(double(rgb2gray(frame_rot)) - double(bg_gray));
cam_mask = diff_img > S.BODY_BG_DIFF_THRESH;
cam_mask = imclose(cam_mask, strel('disk', S.BODY_CLOSE_RADIUS));
cam_mask = imopen(cam_mask, strel('disk', S.BODY_OPEN_RADIUS));
cam_mask = imfill(cam_mask, 'holes');

cc = bwconncomp(cam_mask);
props = regionprops(cc, 'Area', 'PixelIdxList');
cam_mask(:) = false;
for k = 1:numel(props)
    if props(k).Area >= S.BODY_MIN_BLOB_AREA
        cam_mask(props(k).PixelIdxList) = true;
    end
end

cc2 = bwconncomp(cam_mask);
if cc2.NumObjects > 0
    sizes = cellfun(@numel, cc2.PixelIdxList);
    [~, largest] = max(sizes);
    cam_mask(:) = false;
    cam_mask(cc2.PixelIdxList{largest}) = true;
end

ref_out = imref2d([S.BOARD_SIZE * S.GRID_ROWS, S.BOARD_SIZE * S.GRID_COLS]);
mask = imwarp(uint8(cam_mask) * 255, tform, 'OutputView', ref_out) > 128;
cc3 = bwconncomp(mask);
if cc3.NumObjects > 1
    sizes = cellfun(@numel, cc3.PixelIdxList);
    [~, largest] = max(sizes);
    mask(:) = false;
    mask(cc3.PixelIdxList{largest}) = true;
end
end

function frame = apply_frame_transform(frame, frame_transform)
switch lower(char(frame_transform))
    case 'rot180'
        frame = rot90(frame, 2);
    case {'none', 'raw'}
    otherwise
        error('Unknown frame transform: %s', frame_transform);
end
end

function [fd, kmax] = higuchi_fd_2d(x, y)
% Higuchi fractal dimension of a 2-D trajectory.
fd = NaN;
n = numel(x);
kmax = min(20, floor(n / 4));
if n < 12 || kmax < 3
    kmax = NaN;
    return;
end

L = nan(kmax, 1);
for k = 1:kmax
    Lm = nan(k, 1);
    for m = 1:k
        idx = m:k:n;
        if numel(idx) < 2
            continue;
        end
        d = hypot(diff(x(idx)), diff(y(idx)));
        n_segments = numel(idx) - 1;
        scale = (n - 1) / (n_segments * k);
        Lm(m) = sum(d, 'omitnan') * scale / k;
    end
    L(k) = mean(Lm, 'omitnan');
end

ok = L > 0 & isfinite(L);
if sum(ok) < 3
    return;
end
p = polyfit(log(1 ./ find(ok)'), log(L(ok)), 1);
fd = p(1);
end

function ti = compute_tortuosity(raw, i0, i1)
stats = bout_stats(raw, i0, i1);
ti = stats.tortuosity;
end

function T = raw_recording_table(raw_results)
rows = {};
for i = 1:numel(raw_results)
    rows(end+1, :) = {raw_results(i).recording_date, ...
        raw_results(i).days_from_surgery, raw_results(i).rat, ...
        raw_results(i).group, raw_results(i).surgery_phase, ...
        raw_results(i).output_name, raw_results(i).input_file, ...
        raw_results(i).n_bouts, raw_results(i).fs}; %#ok<AGROW>
end
names = {'recording_date', 'days_from_surgery', 'rat', 'group', ...
    'surgery_phase', 'output_name', 'input_file', 'n_bouts', 'fs'};
if isempty(rows)
    T = cell2table(cell(0, numel(names)), 'VariableNames', names);
else
    T = cell2table(rows, 'VariableNames', names);
end
end

function corrections = read_corrections(path_value)
if exist(path_value, 'file')
    corrections = readtable(path_value, 'TextType', 'string', ...
        'Delimiter', ',', 'VariableNamingRule', 'preserve');
else
    corrections = table();
end
end

function corr = find_correction(output_name, bout_index, corrections)
corr = [];
if isempty(corrections) || ~ismember("output_name", string(corrections.Properties.VariableNames))
    return;
end
idx = corrections.output_name == string(output_name) & ...
    corrections.bout_index == bout_index;
if any(idx)
    row = corrections(find(idx, 1, 'last'), :);
    corr = table2struct(row);
end
end

function corrections = upsert_correction(corrections, row)
if isempty(corrections)
    corrections = row;
    return;
end
idx = corrections.output_name == row.output_name & ...
    corrections.bout_index == row.bout_index;
corrections(idx, :) = [];
corrections = [corrections; row];
end

function n = count_corrected_bouts(output_name, corrections)
n = 0;
if isempty(corrections) || ~ismember("output_name", string(corrections.Properties.VariableNames))
    return;
end
n = numel(unique(corrections.bout_index(corrections.output_name == string(output_name))));
end

function configure_slider(h, min_value, max_value, value)
set(h, 'Min', min_value, 'Max', max_value, 'Value', value);
if max_value > min_value
    set(h, 'SliderStep', [1 10] ./ max(1, max_value - min_value));
end
end

function id = board_id_for_name_or_data(tac, name, S)
id = NaN;
id_field = [name '_board_ids'];
if isfield(tac, id_field)
    board_ids = tac.(id_field);
    if isnumeric(board_ids)
        id = double(board_ids(1));
    elseif iscell(board_ids) && ~isempty(board_ids)
        id = double(board_ids{1});
    end
end
if isnan(id)
    parsed = sscanf(name, 'Board%d');
    if ~isempty(parsed), id = parsed; end
end
if isnan(id) || id < 1 || id > S.MAX_BOARD_ID
    id = NaN;
end
end

function img = apply_transform(img, type)
switch string(type)
    case "rot180"
        img = rot90(img, 2);
    case "rot90"
        img = rot90(img, 1);
    case "rot270"
        img = rot90(img, 3);
    case "fliplr"
        img = fliplr(img);
    case "flipud"
        img = flipud(img);
end
end

function [r, c] = pressure_index_to_coords(idx)
if idx < 2048
    r = floor(double(idx) / 32) + 1;
    c = mod(double(idx), 32) + 1;
else
    r = floor((double(idx) - 2048) / 32) + 1;
    c = mod(double(idx) - 2048, 32) + 33;
end
end

function meta = parse_recording_metadata(output_name, surgery_date)
tokens = regexp(char(output_name), ...
    '^(\d{4})_(\d{2})_(\d{2})_rat(\d+)_', 'tokens', 'once');
if isempty(tokens)
    meta.recording_date = NaT;
    meta.rat = NaN;
else
    meta.recording_date = datetime(str2double(tokens{1}), ...
        str2double(tokens{2}), str2double(tokens{3}));
    meta.rat = str2double(tokens{4});
end
meta.days_from_surgery = days(meta.recording_date - surgery_date);
if ismember(meta.rat, [1 2])
    meta.group = "sham";
else
    meta.group = "sciatic_nerve_pinch";
end
if meta.recording_date < surgery_date
    meta.surgery_phase = "pre_surgery";
else
    meta.surgery_phase = "post_surgery";
end
end

function epoch = epoch_for_days(days_from_surgery)
if days_from_surgery < 0
    epoch = "pre";
elseif days_from_surgery <= 3
    epoch = "early_post";
else
    epoch = "late_post";
end
end

function y = sem_value(x)
x = x(~isnan(x));
if isempty(x)
    y = NaN;
else
    y = std(x) / sqrt(numel(x));
end
end

function raw = empty_recording_result()
raw = struct('recording_date', NaT, 'days_from_surgery', NaN, ...
    'rat', NaN, 'group', "", 'surgery_phase', "", 'output_name', "", ...
    'input_file', "", 't', [], 'source_t', [], 'cop_x_mm', [], ...
    'cop_y_mm', [], 'raw_cop_x_mm', [], 'raw_cop_y_mm', [], ...
    'geom_centroid_x_mm', [], 'geom_centroid_y_mm', [], ...
    'raw_geom_centroid_x_mm', [], 'raw_geom_centroid_y_mm', [], ...
    'total_pressure', [], 'n_active_px', [], 'velocity_mm_s', [], ...
    'geom_centroid_velocity_mm_s', [], ...
    'is_moving', [], 'bout_starts', [], 'bout_ends', [], 'n_bouts', 0, ...
    'fs', NaN);
end

function ensure_dir(path_name)
if ~exist(path_name, 'dir')
    mkdir(path_name);
end
end

function [bouts, info] = detect_walking_bouts(frames, time, opts)
% Walking runs ([t_start t_end] per row) from the COP trace: sustained travel
% along x with velocity hysteresis, displacement and straightness checks.
% Default thresholds are conservative; opts.preset = 'review' relaxes them to
% propose candidates for manual review.

if nargin < 3, opts = struct(); end
p = struct('win_s', 1.0, 'v_hi', 70, 'v_lo', 15, 'gap_s', 2.5, 'v_edge', 40, ...
    'min_dur', 1.2, 'min_dx', 160, 'min_straight', 0.6, 'pad_s', 0, 'pad_tol_mm', 20, ...
    'ignore_first_s', 5.0, 'pressure_thres', 700, 'min_total_pressure', 105000, ...
    'max_bridge_s', 0.25, 'max_jump_speed', 1000, 'pixel_mm', 2.0, 'target_fs', 100);
if isfield(opts, 'preset') && strcmpi(opts.preset, 'review')
    p.win_s = 0.8; p.v_hi = 60; p.v_lo = 10; p.gap_s = 3.5; p.v_edge = 30;
    p.min_dur = 0.6; p.min_dx = 120; p.min_straight = 0.4; p.pad_s = 0.5;
end
f = setdiff(fieldnames(opts), {'preset'});
for k = 1:numel(f), p.(f{k}) = opts.(f{k}); end

if isstruct(frames)
    t = double(frames.t(:)); cx = double(frames.cop_x_mm(:));
    cy = double(frames.cop_y_mm(:)); tp = double(frames.total_pressure(:));
else
    [t, cx, cy, tp] = cop_from_movie(frames, time, p);
end
n = numel(t);
fs = 1 / median(diff(t), 'omitnan');

% --- 1. usable samples and data pieces -----------------------------------
brk = [false; diff(t) > p.max_bridge_s];
seg = cumsum(brk) + 1;
valid = tp >= p.min_total_pressure & ~isnan(cx);
ok = valid;
[a, b] = runs(~valid);
for k = 1:numel(a)
    if a(k) > 1 && b(k) < n && t(b(k)) - t(a(k)) <= p.max_bridge_s && seg(a(k)-1) == seg(b(k)+1)
        ok(a(k):b(k)) = true;
    end
end
cx(~valid) = NaN; cy(~valid) = NaN;
w = max(1, round(0.2 * fs));
xs = nan(n, 1); ys = nan(n, 1);
for s = unique(seg)'
    m = seg == s;
    xs(m) = movmean(fill_inside(cx(m)), w, 'omitnan');
    ys(m) = movmean(fill_inside(cy(m)), w, 'omitnan');
end
xs(~ok) = NaN; ys(~ok) = NaN;

% --- 2. direction-consistent runs ----------------------------------------
h = max(1, round(p.win_s * fs / 2));
v = wvel(t, xs, seg, h);
vs = wvel(t, xs, seg, max(1, round(0.3 * fs / 2)));
runs_dr = zeros(0, 3);
for dr = [1 -1]
    core = v * dr >= p.v_hi;
    ext = v * dr >= p.v_lo & ok;
    [a, b] = runs(ext);
    for k = 1:numel(a)
        if any(core(a(k):b(k))), runs_dr(end+1, :) = [a(k) b(k) dr]; end %#ok<AGROW>
    end
end
runs_dr = sortrows(runs_dr, 1);
merged = zeros(0, 3);
for k = 1:size(runs_dr, 1)
    if ~isempty(merged) && merged(end, 3) == runs_dr(k, 3) && ...
            t(runs_dr(k, 1)) - t(merged(end, 2)) <= p.gap_s && ...
            joinable(merged(end, 2), runs_dr(k, 1), runs_dr(k, 3))
        merged(end, 2) = runs_dr(k, 2);
    else
        merged(end+1, :) = runs_dr(k, :); %#ok<AGROW>
    end
end

% --- 3./4. edges and bout filters ----------------------------------------
kept = zeros(0, 2); stats = zeros(0, 3);
for k = 1:size(merged, 1)
    a = merged(k, 1); b = merged(k, 2); dr = merged(k, 3);
    lo = max(1, a - h); hi = min(n, b + h);
    lo = lo - 1 + find(seg(lo:hi) == seg(a), 1, 'first');
    hi = lo - 1 + find(seg(lo:hi) == seg(b), 1, 'last');
    mv = vs(lo:hi) * dr >= p.v_edge & ok(lo:hi);
    if ~any(mv), continue; end
    s = lo - 1 + find(mv, 1, 'first');
    e = lo - 1 + find(mv, 1, 'last');
    if t(s) - t(1) < p.ignore_first_s || e <= s, continue; end
    xx = xs(s:e); yy = ys(s:e); g = ~isnan(xx);
    if nnz(g) < 3, continue; end
    xx = xx(g); yy = yy(g);
    path = sum(hypot(diff(xx), diff(yy)));
    dur = t(e) - t(s);
    dx = (xx(end) - xx(1)) * dr;
    st = hypot(xx(end) - xx(1), yy(end) - yy(1)) / max(path, eps);
    if dur >= p.min_dur && dx >= p.min_dx && st >= p.min_straight
        kept(end+1, :) = [s e]; %#ok<AGROW>
        stats(end+1, :) = [dur dx st]; %#ok<AGROW>
    end
end
[kept, order] = sortrows(kept, 1);
stats = stats(order, :);
mm = zeros(0, 2); mstats = zeros(0, 3);
for k = 1:size(kept, 1)
    if ~isempty(mm) && kept(k, 1) <= mm(end, 2)
        mm(end, 2) = max(mm(end, 2), kept(k, 2));
        mstats(end, :) = max(mstats(end, :), stats(k, :));
    else
        mm(end+1, :) = kept(k, :); %#ok<AGROW>
        mstats(end+1, :) = stats(k, :); %#ok<AGROW>
    end
end
% Pad only while the animal stays within pad_tol_mm; recheck displacement.
padn = round(p.pad_s * fs);
bouts = zeros(0, 2); fstats = zeros(0, 3);
for k = 1:size(mm, 1)
    s = mm(k, 1); e = mm(k, 2);
    lo = max(1, s - padn); hi = min(n, e + padn);
    if k > 1, lo = max(lo, floor((mm(k-1, 2) + s) / 2) + 1); end
    if k < size(mm, 1), hi = min(hi, floor((e + mm(k+1, 1)) / 2)); end
    i = s;
    while i - 1 >= lo && still(i - 1, s), i = i - 1; end
    j = e;
    while j + 1 <= hi && still(j + 1, e), j = j + 1; end
    g = find(~isnan(xs(i:j)));
    if numel(g) < 2, continue; end
    a = i - 1 + g(1); b = i - 1 + g(end);
    disp_mm = hypot(xs(b) - xs(a), ys(b) - ys(a));
    if disp_mm < p.min_dx, continue; end
    bouts(end+1, :) = [t(i) t(j)]; %#ok<AGROW>
    fstats(end+1, :) = [t(j) - t(i), disp_mm, mstats(k, 3)]; %#ok<AGROW>
end
info = struct('params', p, 't', t, 'cop_x_mm', xs, 'cop_y_mm', ys, ...
    'velocity_x_mm_s', v, 'bout_stats', fstats);

    function tf = still(q, ref)
        tf = seg(q) == seg(ref) && ok(q) && ~isnan(xs(q)) && ...
            abs(xs(q) - xs(ref)) <= p.pad_tol_mm && abs(ys(q) - ys(ref)) <= p.pad_tol_mm;
    end

    function tf = joinable(i, j, dr)
        % Same piece: every sample between the runs must be usable. Across a
        % time hole: the COP jump over each hole goes the travel direction at
        % a plausible speed.
        if seg(i) == seg(j)
            tf = all(ok(i:j));
            return;
        end
        r = i:j;
        tf = all(ok(r(seg(r) == seg(i)))) && all(ok(r(seg(r) == seg(j))));
        for q = r(2:end)
            if ~tf, return; end
            if brk(q)
                jump = (xs(q) - xs(q-1)) * dr;
                tf = ~isnan(jump) && jump >= -10 && abs(jump) / (t(q) - t(q-1)) <= p.max_jump_speed;
            end
        end
    end
end

function [t, cx, cy, tp] = cop_from_movie(frames, time, p)
time = double(time(:));
ds = max(1, round((1 / median(diff(time), 'omitnan')) / p.target_fs));
idx = 1:ds:numel(time);
t = time(idx); n = numel(t);
cx = nan(n, 1); cy = nan(n, 1); tp = zeros(n, 1);
for k = 1:n
    fr = double(frames(:, :, idx(k)));
    m = fr > p.pressure_thres;
    [rr, cc] = find(m);
    if numel(rr) < 2, continue; end
    w = fr(m); sw = sum(w);
    if sw <= 0, continue; end
    cx(k) = sum(cc .* w) / sw * p.pixel_mm;
    cy(k) = sum(rr .* w) / sw * p.pixel_mm;
    tp(k) = sw;
end
[cx, cy] = smooth_cop__detect_walking_bouts(cx, cy, 1 / median(diff(t), 'omitnan'));
end

function [xf, yf] = smooth_cop__detect_walking_bouts(x, y, fs)
% Same smoothing as smooth_cop.
xf = x; yf = y;
ok = ~isnan(x) & ~isnan(y);
if nnz(ok) <= 10, return; end
xi = (1:numel(x))';
xf(~ok) = interp1(xi(ok), x(ok), xi(~ok), 'nearest', 'extrap');
yf(~ok) = interp1(xi(ok), y(ok), xi(~ok), 'nearest', 'extrap');
xf = medfilt1(xf, 10); yf = medfilt1(yf, 10);
if 3.0 < fs / 2
    [bb, aa] = butter(4, 3.0 / (fs / 2), 'low');
    xf = filtfilt(bb, aa, xf); yf = filtfilt(bb, aa, yf);
end
xf(~ok) = NaN; yf(~ok) = NaN;
end

function v = wvel(t, x, seg, h)
% Centred velocity over +-h samples, zero where the window spans a time hole.
v = zeros(numel(t), 1);
i = (h + 1):(numel(t) - h);
same = seg(i + h) == seg(i - h);
v(i) = (x(i + h) - x(i - h)) ./ (t(i + h) - t(i - h));
v(i(~same)) = 0;
v(isnan(v)) = 0;
end

function [a, b] = runs(mask)
d = diff([false; mask(:); false]);
a = find(d == 1); b = find(d == -1) - 1;
end

function x = fill_inside(x)
% Linear interpolation of interior NaNs only (edges stay NaN).
g = find(~isnan(x));
if numel(g) < 2, return; end
i = g(1):g(end);
x(i) = interp1(g, x(g), i, 'linear');
end
