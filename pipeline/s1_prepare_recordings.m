function out = s1_prepare_recordings(action, only)
% Background models for s2 ("backgrounds"); for new data, choose videos
% ("pick"), click the platform corners ("corners") and build a new
% recording list ("background").

if nargin < 1, action = "all"; end
if nargin < 2, only = []; end
action = lower(string(action));
if action == "backgrounds"
    out = backgrounds_from_recording_list(only);
    return;
end
cfg = gait_config();
cfg.recording_list_path = fullfile(cfg.work_root, 'setup', 'recordings.csv');
out = [];
if any(action == ["pick", "all"]), out = step_1_pick_overhead_videos(cfg); end
if any(action == ["corners", "all"]), out = step_2_calibrate_platform_corners(cfg); end
if any(action == ["background", "all"]), out = step_3_build_background_models_and_recordings(cfg); end
if ~any(action == ["pick", "corners", "background", "all"])
    error('Unknown action "%s" (backgrounds, pick, corners, background, all).', action);
end
end

function T = backgrounds_from_recording_list(only)
[cfg, R] = gait_config(only);
if ~exist(cfg.background_model_output_root, 'dir'), mkdir(cfg.background_model_output_root); end
transform = read_template_frame_transform(cfg);
status = strings(height(R), 1);
for i = 1:height(R)
    if isfile(R.background_path(i)), status(i) = "exists"; continue; end
    fprintf('[%d/%d] background %s\n', i, height(R), R.output_name(i));
    bg_model = build_background_model(R.camera1_path(i), cfg.background_model_n_frames, transform);
    save_background_model(R.background_path(i), bg_model, R.camera1_path(i), cfg.background_model_n_frames, transform);
    status(i) = "built";
end
T = table(R.output_name, status, 'VariableNames', {'output_name', 'status'});
end

function selections = step_1_pick_overhead_videos(cfg)
%STEP_1_PICK_OVERHEAD_VIDEOS GUI for choosing the overhead camera.
%
%   selections = step_1_pick_overhead_videos()
%   selections = step_1_pick_overhead_videos(cfg)
%
% The GUI scans <date>/runway/rat<N> folders under cfg.rat_data_root for the
% rats in cfg.included_rats and dates on or after cfg.first_recording_date,
% and writes the selected overhead videos to cfg.video_selection_path.

if nargin < 1 || isempty(cfg)
    cfg = gait_config();
end

records = find_recordings(cfg);
if isempty(records)
    error('No matching runway recordings found under %s.', cfg.rat_data_root);
end

selections_path = cfg.video_selection_path;
ensure_dir(fileparts(selections_path));
records = merge_existing_selections(records, selections_path);
if isfield(cfg, 'launch_video_picker_gui') && ~cfg.launch_video_picker_gui
    selections = records_to_table(records);
    return;
end

state.records = records;
state.index = first_unselected_index(records);
state.selections_path = selections_path;
state.frame_fraction = 0.35;
state.current_frame = [];

fig = figure('Name', 'Pick Overhead Videos', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'ToolBar', 'none', 'Color', [0.96 0.96 0.96], ...
    'Position', [80 80 1280 780], 'CloseRequestFcn', @close_request);

state.ax = axes('Parent', fig, 'Units', 'normalized', ...
    'Position', [0.04 0.18 0.62 0.74]);
axis(state.ax, 'off');

state.title_text = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.04 0.93 0.92 0.045], 'HorizontalAlignment', 'left', ...
    'FontSize', 12, 'FontWeight', 'bold', 'BackgroundColor', fig.Color);
state.detail_text = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.69 0.78 0.28 0.14], 'HorizontalAlignment', 'left', ...
    'FontSize', 10, 'BackgroundColor', fig.Color);
state.video_list = uicontrol(fig, 'Style', 'listbox', 'Units', 'normalized', ...
    'Position', [0.69 0.42 0.28 0.34], 'FontSize', 10, ...
    'Callback', @video_changed);
state.notes_edit = uicontrol(fig, 'Style', 'edit', 'Units', 'normalized', ...
    'Position', [0.69 0.31 0.28 0.08], 'FontSize', 10, ...
    'HorizontalAlignment', 'left', 'Max', 2, 'Callback', @notes_changed);
state.status_text = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.04 0.08 0.62 0.06], 'HorizontalAlignment', 'left', ...
    'FontSize', 10, 'BackgroundColor', fig.Color);

uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.69 0.24 0.13 0.045], 'String', 'Mark Selected', ...
    'FontSize', 10, 'Callback', @mark_selected);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.84 0.24 0.13 0.045], 'String', 'Clear', ...
    'FontSize', 10, 'Callback', @clear_selection);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.69 0.18 0.13 0.045], 'String', 'Previous', ...
    'FontSize', 10, 'Callback', @previous_record);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.84 0.18 0.13 0.045], 'String', 'Next', ...
    'FontSize', 10, 'Callback', @next_record);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.69 0.10 0.13 0.05], 'String', 'Save CSV', ...
    'FontSize', 10, 'Callback', @save_clicked);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.84 0.10 0.13 0.05], 'String', 'Done', ...
    'FontSize', 10, 'Callback', @done_clicked);

guidata(fig, state);
refresh_gui(fig);
uiwait(fig);

if ishandle(fig)
    state = guidata(fig);
    selections = records_to_table(state.records);
    delete(fig);
else
    selections = records_to_table(records);
end

    function video_changed(src, ~)
        state = guidata(src);
        state.records(state.index).candidate_index = get(src, 'Value');
        guidata(src, state);
        refresh_gui(src);
    end

    function notes_changed(src, ~)
        state = guidata(src);
        state.records(state.index).notes = string(get(src, 'String'));
        guidata(src, state);
    end

    function mark_selected(src, ~)
        state = guidata(src);
        rec = state.records(state.index);
        if isempty(rec.video_files)
            rec.selection_status = "no_video_candidates";
            rec.selected_video = "";
            rec.selected_camera = "";
        else
            rec.selected_video = string(rec.video_files{rec.candidate_index});
            rec.selected_camera = camera_name(rec.selected_video);
            rec.selection_status = "selected";
        end
        rec.updated_at = string(datetime('now'));
        state.records(state.index) = rec;
        guidata(src, state);
        save_records(state);
        next_unselected_or_next(src);
    end

    function clear_selection(src, ~)
        state = guidata(src);
        state.records(state.index).selected_video = "";
        state.records(state.index).selected_camera = "";
        state.records(state.index).selection_status = "unselected";
        state.records(state.index).updated_at = string(datetime('now'));
        guidata(src, state);
        refresh_gui(src);
    end

    function previous_record(src, ~)
        state = guidata(src);
        state.index = max(1, state.index - 1);
        guidata(src, state);
        refresh_gui(src);
    end

    function next_record(src, ~)
        state = guidata(src);
        state.index = min(numel(state.records), state.index + 1);
        guidata(src, state);
        refresh_gui(src);
    end

    function save_clicked(src, ~)
        state = guidata(src);
        save_records(state);
        refresh_gui(src);
    end

    function done_clicked(src, ~)
        state = guidata(src);
        save_records(state);
        guidata(src, state);
        uiresume(ancestor(src, 'figure'));
    end

    function close_request(src, ~)
        state = guidata(src);
        save_records(state);
        guidata(src, state);
        uiresume(src);
    end
end

function records = find_recordings(cfg)
date_dirs = dir(cfg.rat_data_root);
date_dirs = date_dirs([date_dirs.isdir]);
records = empty_record();
records(1) = [];

for i = 1:numel(date_dirs)
    folder_name = date_dirs(i).name;
    rec_date = parse_date_folder(folder_name);
    if isnat(rec_date) || rec_date < cfg.first_recording_date
        continue;
    end

    runway_dir = fullfile(date_dirs(i).folder, folder_name, 'runway');
    if ~exist(runway_dir, 'dir')
        continue;
    end

    for rat_num = cfg.included_rats
        rat_dir = fullfile(runway_dir, sprintf('rat%d', rat_num));
        if ~exist(rat_dir, 'dir')
            continue;
        end

        tactile_files = list_files(rat_dir, 'runway_tactile_data_*.mat');
        video_files = list_video_candidates(rat_dir);
        if isempty(tactile_files) && isempty(video_files)
            continue;
        end

        rec = empty_record();
        rec.enabled = true;
        rec.recording_date = rec_date;
        rec.date_folder = string(folder_name);
        rec.rat = rat_num;
        rec.group = surgery_group(rat_num);
        rec.surgery_phase = surgery_phase(rec_date, cfg.surgery_date);
        rec.recording_folder = string(rat_dir);
        rec.tactile_file = first_or_empty(tactile_files);
        rec.video_files = video_files;
        rec.video_candidates = string(strjoin(cellfun(@string, video_files), '|'));
        rec.candidate_index = default_candidate_index(video_files);
        rec.selected_video = "";
        rec.selected_camera = "";
        rec.selection_status = "unselected";
        rec.notes = "";
        rec.updated_at = "";
        records(end+1) = rec; %#ok<AGROW>
    end
end

[~, order] = sortrows(table([records.recording_date]', [records.rat]'));
records = records(order);
end

function records = merge_existing_selections(records, selections_path)
if ~exist(selections_path, 'file')
    return;
end

old = readtable(selections_path, 'TextType', 'string', ...
    'Delimiter', ',', 'VariableNamingRule', 'preserve');
if ~all(ismember(["recording_folder", "selected_video"], ...
        string(old.Properties.VariableNames)))
    return;
end

for i = 1:numel(records)
    key = string(records(i).recording_folder);
    idx = find(old.recording_folder == key, 1, 'last');
    if isempty(idx)
        continue;
    end
    records(i).selected_video = old.selected_video(idx);
    if ismember("selected_camera", string(old.Properties.VariableNames))
        records(i).selected_camera = old.selected_camera(idx);
    else
        records(i).selected_camera = camera_name(records(i).selected_video);
    end
    if ismember("selection_status", string(old.Properties.VariableNames))
        records(i).selection_status = old.selection_status(idx);
    elseif strlength(records(i).selected_video) > 0
        records(i).selection_status = "selected";
    end
    if ismember("notes", string(old.Properties.VariableNames))
        records(i).notes = old.notes(idx);
    end
    if ismember("updated_at", string(old.Properties.VariableNames))
        records(i).updated_at = old.updated_at(idx);
    end

    candidate_match = find(strcmp(records(i).video_files, ...
        char(records(i).selected_video)), 1);
    if ~isempty(candidate_match)
        records(i).candidate_index = candidate_match;
    end
end
end

function refresh_gui(src)
fig = ancestor(src, 'figure');
state = guidata(fig);
rec = state.records(state.index);

set(state.title_text, 'String', sprintf( ...
    '%d/%d  %s  rat%d  %s  %s', state.index, numel(state.records), ...
    rec.date_folder, rec.rat, rec.group, rec.surgery_phase));

detail = sprintf(['Folder:\n%s\n\nTactile:\n%s\n\nSelected:\n%s\n\n' ...
    'CSV:\n%s'], rec.recording_folder, rec.tactile_file, ...
    rec.selected_video, state.selections_path);
set(state.detail_text, 'String', detail);
set(state.notes_edit, 'String', char(rec.notes));

if isempty(rec.video_files)
    set(state.video_list, 'String', {'<no video candidates>'}, 'Value', 1);
    cla(state.ax);
    text(state.ax, 0.5, 0.5, 'No video candidates', ...
        'HorizontalAlignment', 'center');
else
    names = cellfun(@(p) char(strip_root(p, rec.recording_folder)), ...
        rec.video_files, 'UniformOutput', false);
    set(state.video_list, 'String', names, 'Value', rec.candidate_index);
    show_video_frame(state.ax, rec.video_files{rec.candidate_index}, ...
        state.frame_fraction);
end

n_selected = sum([state.records.selection_status] == "selected");
status = sprintf('%d selected / %d total. Current status: %s', ...
    n_selected, numel(state.records), rec.selection_status);
set(state.status_text, 'String', status);
guidata(fig, state);
end

function show_video_frame(ax, video_path, frame_fraction)
cla(ax);
try
    vr = VideoReader(video_path);
    vr.CurrentTime = max(0, min(vr.Duration * frame_fraction, ...
        max(0, vr.Duration - 1 / vr.FrameRate)));
    frame = readFrame(vr);
    imshow(frame, 'Parent', ax);
    title(ax, video_path, 'Interpreter', 'none', 'FontSize', 9);
catch ME
    text(ax, 0.5, 0.5, sprintf('Could not preview video:\n%s', ME.message), ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');
    axis(ax, 'off');
end
end

function next_unselected_or_next(src)
state = guidata(src);
remaining = find([state.records.selection_status] ~= "selected");
remaining = remaining(remaining > state.index);
if ~isempty(remaining)
    state.index = remaining(1);
else
    state.index = min(numel(state.records), state.index + 1);
end
guidata(src, state);
refresh_gui(src);
end

function save_records(state)
T = records_to_table(state.records);
writetable(T, state.selections_path);
fprintf('Saved overhead video selections: %s\n', state.selections_path);
end

function T = records_to_table(records)
T = table();
T.enabled = [records.enabled]';
recording_dates = [records.recording_date]';
recording_dates.Format = 'yyyy-MM-dd';
T.recording_date = string(recording_dates);
T.date_folder = [records.date_folder]';
T.rat = [records.rat]';
T.group = [records.group]';
T.surgery_phase = [records.surgery_phase]';
T.recording_folder = [records.recording_folder]';
T.tactile_file = [records.tactile_file]';
T.video_candidates = [records.video_candidates]';
T.selected_video = [records.selected_video]';
T.selected_camera = [records.selected_camera]';
T.selection_status = [records.selection_status]';
T.notes = [records.notes]';
T.updated_at = [records.updated_at]';
end

function rec = empty_record()
rec = struct('enabled', true, 'recording_date', NaT, 'date_folder', "", ...
    'rat', NaN, 'group', "", 'surgery_phase', "", ...
    'recording_folder', "", 'tactile_file', "", 'video_files', {{}}, ...
    'video_candidates', "", 'candidate_index', 1, 'selected_video', "", ...
    'selected_camera', "", 'selection_status', "unselected", ...
    'notes', "", 'updated_at', "");
end

function dt = parse_date_folder(folder_name)
dt = NaT;
try
    token = regexp(folder_name, '^\d{1,2}-\d{1,2}-\d{4}', 'match', 'once');
    if ~isempty(token)
        dt = datetime(token, 'InputFormat', 'M-d-yyyy');
    end
catch
    dt = NaT;
end
end

function files = list_files(folder_path, pattern)
listing = dir(fullfile(folder_path, pattern));
listing = listing(~[listing.isdir]);
files = arrayfun(@(f) string(fullfile(f.folder, f.name)), listing, ...
    'UniformOutput', false);
end

function files = list_video_candidates(folder_path)
listing = [dir(fullfile(folder_path, '*.mp4')); ...
    dir(fullfile(folder_path, '*.avi'))];
listing = listing(~[listing.isdir]);
names = lower(string({listing.name}));
derived = contains(names, "side_by_side") | contains(names, "overlaid") | ...
    contains(names, "tactile_output") | contains(names, "segmentation");
listing = listing(~derived);
files = arrayfun(@(f) string(fullfile(f.folder, f.name)), listing, ...
    'UniformOutput', false);
end

function value = first_or_empty(values)
if isempty(values)
    value = "";
else
    value = string(values{1});
end
end

function idx = default_candidate_index(video_files)
idx = 1;
if isempty(video_files)
    return;
end
names = lower(string(video_files));
cam0 = find(contains(names, "camera_0"), 1);
if ~isempty(cam0)
    idx = cam0;
end
end

function label = surgery_group(rat_num)
if ismember(rat_num, [1 2])
    label = "sham";
else
    label = "sciatic_nerve_pinch";
end
end

function label = surgery_phase(recording_date, surgery_date)
if recording_date < surgery_date
    label = "pre_surgery";
else
    label = "post_surgery";
end
end

function cam = camera_name(video_path)
cam = "";
token = regexp(char(video_path), 'camera_(\d+)', 'tokens', 'once');
if ~isempty(token)
    cam = "camera_" + string(token{1});
end
end

function value = strip_root(path_value, root_value)
value = erase(string(path_value), string(root_value) + filesep);
end

function idx = first_unselected_index(records)
idx = find([records.selection_status] ~= "selected", 1);
if isempty(idx)
    idx = 1;
end
end

function ensure_dir(path_value)
if ~exist(path_value, 'dir')
    mkdir(path_value);
end
end

function calibrations = step_2_calibrate_platform_corners(cfg)
%STEP_2_CALIBRATE_PLATFORM_CORNERS Infer sensor corners from platform clicks.
%
%   calibrations = step_2_calibrate_platform_corners()
%   calibrations = step_2_calibrate_platform_corners(cfg)
%
% This GUI reads cfg.video_selection_path, loops through the selected
% overhead videos, asks for four platform corners, then uses
% data/platform_sheet_template.mat to infer the pressure-sheet corners and
% save one homography per recording.

if nargin < 1 || isempty(cfg)
    cfg = gait_config();
end

validate_file(cfg.video_selection_path, 'overhead video selections CSV');
validate_file(cfg.platform_template_path, 'platform sheet template');
ensure_dir(cfg.homography_output_root);
ensure_dir(fileparts(cfg.platform_calibration_path));

template_data = load(cfg.platform_template_path, 'template');
if ~isfield(template_data, 'template')
    error('Template file does not contain variable "template": %s', ...
        cfg.platform_template_path);
end
template = template_data.template;

records = load_selected_records(cfg.video_selection_path);
records = merge_existing_calibrations(records, cfg.platform_calibration_path);
if isempty(records)
    error('No selected overhead videos found in %s.', cfg.video_selection_path);
end

if isfield(cfg, 'launch_platform_calibration_gui') && ...
        ~cfg.launch_platform_calibration_gui
    calibrations = records_to_table__step_2_calibrate_platform_corners(records);
    return;
end

state.records = records;
state.template = template;
state.template_path = cfg.platform_template_path;
state.output_root = cfg.homography_output_root;
state.calibration_path = cfg.platform_calibration_path;
state.frame_fraction = 0.35;
state.index = first_uncalibrated_index(records);
state.click_pts = zeros(0, 2);
state.h_markers = gobjects(0);
state.h_lines = gobjects(0);

fig = figure('Name', 'Click Platform Corners', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'ToolBar', 'none', 'Color', [0.96 0.96 0.96], ...
    'Position', [70 70 1340 820], 'CloseRequestFcn', @close_request);

state.ax = axes('Parent', fig, 'Units', 'normalized', ...
    'Position', [0.04 0.15 0.64 0.78]);
state.title_text = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.04 0.94 0.92 0.04], 'HorizontalAlignment', 'left', ...
    'FontSize', 12, 'FontWeight', 'bold', 'BackgroundColor', fig.Color);
state.detail_text = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.71 0.73 0.26 0.20], 'HorizontalAlignment', 'left', ...
    'FontSize', 10, 'BackgroundColor', fig.Color);
state.instruction_text = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.04 0.07 0.64 0.055], 'HorizontalAlignment', 'left', ...
    'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', fig.Color);
state.notes_edit = uicontrol(fig, 'Style', 'edit', 'Units', 'normalized', ...
    'Position', [0.71 0.58 0.26 0.08], 'FontSize', 10, ...
    'HorizontalAlignment', 'left', 'Max', 2, 'Callback', @notes_changed);
state.status_text = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.71 0.50 0.26 0.055], 'HorizontalAlignment', 'left', ...
    'FontSize', 10, 'BackgroundColor', fig.Color);

uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.71 0.42 0.12 0.045], 'String', 'Start Clicks', ...
    'FontSize', 10, 'Callback', @start_clicks);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.85 0.42 0.12 0.045], 'String', 'Undo Click', ...
    'FontSize', 10, 'Callback', @undo_click);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.71 0.36 0.12 0.045], 'String', 'Save Homography', ...
    'FontSize', 10, 'Callback', @save_homography_clicked);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.85 0.36 0.12 0.045], 'String', 'Clear', ...
    'FontSize', 10, 'Callback', @clear_current);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.71 0.29 0.12 0.045], 'String', 'Previous', ...
    'FontSize', 10, 'Callback', @previous_record);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.85 0.29 0.12 0.045], 'String', 'Next', ...
    'FontSize', 10, 'Callback', @next_record);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.71 0.20 0.12 0.05], 'String', 'Save CSV', ...
    'FontSize', 10, 'Callback', @save_csv_clicked);
uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.85 0.20 0.12 0.05], 'String', 'Done', ...
    'FontSize', 10, 'Callback', @done_clicked);

guidata(fig, state);
refresh_gui__step_2_calibrate_platform_corners(fig);
uiwait(fig);

if ishandle(fig)
    state = guidata(fig);
    calibrations = records_to_table__step_2_calibrate_platform_corners(state.records);
    delete(fig);
else
    calibrations = records_to_table__step_2_calibrate_platform_corners(records);
end

    function notes_changed(src, ~)
        state = guidata(src);
        state.records(state.index).notes = string(get(src, 'String'));
        guidata(src, state);
    end

    function start_clicks(src, ~)
        state = guidata(src);
        state.click_pts = zeros(0, 2);
        clear_overlays(state);
        guidata(src, state);
        refresh_gui__step_2_calibrate_platform_corners(src);
        click_four_platform_corners(src);
    end

    function undo_click(src, ~)
        state = guidata(src);
        if ~isempty(state.click_pts)
            state.click_pts(end, :) = [];
        end
        clear_overlays(state);
        guidata(src, state);
        redraw_current_overlays(src);
    end

    function save_homography_clicked(src, ~)
        state = guidata(src);
        if size(state.click_pts, 1) ~= 4
            errordlg('Click all four platform corners first: TL, TR, BR, BL.', ...
                'Missing corners');
            return;
        end
        state = save_current_homography(state);
        guidata(src, state);
        save_records__step_2_calibrate_platform_corners(state);
        next_uncalibrated_or_next(src);
    end

    function clear_current(src, ~)
        state = guidata(src);
        state.click_pts = zeros(0, 2);
        rec = state.records(state.index);
        rec.platform_src_pts = zeros(0, 2);
        rec.sheet_src_pts = zeros(0, 2);
        rec.homography_path = "";
        rec.calibration_status = "uncalibrated";
        rec.updated_at = string(datetime('now'));
        state.records(state.index) = rec;
        clear_overlays(state);
        guidata(src, state);
        refresh_gui__step_2_calibrate_platform_corners(src);
    end

    function previous_record(src, ~)
        state = guidata(src);
        state.index = max(1, state.index - 1);
        state.click_pts = state.records(state.index).platform_src_pts;
        guidata(src, state);
        refresh_gui__step_2_calibrate_platform_corners(src);
    end

    function next_record(src, ~)
        state = guidata(src);
        state.index = min(numel(state.records), state.index + 1);
        state.click_pts = state.records(state.index).platform_src_pts;
        guidata(src, state);
        refresh_gui__step_2_calibrate_platform_corners(src);
    end

    function save_csv_clicked(src, ~)
        state = guidata(src);
        save_records__step_2_calibrate_platform_corners(state);
        refresh_gui__step_2_calibrate_platform_corners(src);
    end

    function done_clicked(src, ~)
        state = guidata(src);
        save_records__step_2_calibrate_platform_corners(state);
        guidata(src, state);
        uiresume(ancestor(src, 'figure'));
    end

    function close_request(src, ~)
        state = guidata(src);
        save_records__step_2_calibrate_platform_corners(state);
        guidata(src, state);
        uiresume(src);
    end
end

function records = load_selected_records(selection_path)
T = readtable(selection_path, 'TextType', 'string', ...
    'Delimiter', ',', 'VariableNamingRule', 'preserve');
required = ["recording_date", "date_folder", "rat", "group", ...
    "surgery_phase", "recording_folder", "tactile_file", ...
    "selected_video", "selection_status"];
for i = 1:numel(required)
    if ~ismember(required(i), string(T.Properties.VariableNames))
        error('Selection CSV is missing required column "%s".', required(i));
    end
end

enabled = true(height(T), 1);
if ismember("enabled", string(T.Properties.VariableNames))
    enabled = parse_enabled(T.enabled);
end
selected = enabled & T.selection_status == "selected" & ...
    strlength(T.selected_video) > 0;
T = T(selected, :);

records = empty_record__step_2_calibrate_platform_corners();
records(1) = [];
for i = 1:height(T)
    rec = empty_record__step_2_calibrate_platform_corners();
    rec.enabled = true;
    rec.recording_date = format_recording_date(T.recording_date(i));
    rec.date_folder = string(T.date_folder(i));
    rec.rat = double(T.rat(i));
    rec.group = string(T.group(i));
    rec.surgery_phase = string(T.surgery_phase(i));
    rec.recording_folder = string(T.recording_folder(i));
    rec.tactile_file = string(T.tactile_file(i));
    rec.selected_video = string(T.selected_video(i));
    rec.platform_src_pts = zeros(0, 2);
    rec.sheet_src_pts = zeros(0, 2);
    rec.homography_path = "";
    rec.calibration_status = "uncalibrated";
    rec.notes = "";
    rec.updated_at = "";
    records(end+1) = rec; %#ok<AGROW>
end
end

function records = merge_existing_calibrations(records, calibration_path)
if ~exist(calibration_path, 'file')
    return;
end

T = readtable(calibration_path, 'TextType', 'string', ...
    'Delimiter', ',', 'VariableNamingRule', 'preserve');
if ~ismember("selected_video", string(T.Properties.VariableNames))
    return;
end

for i = 1:numel(records)
    idx = find(T.selected_video == records(i).selected_video, 1, 'last');
    if isempty(idx)
        continue;
    end
    records(i).homography_path = get_optional_string(T, idx, "homography_path");
    records(i).calibration_status = get_optional_string(T, idx, ...
        "calibration_status");
    if strlength(records(i).calibration_status) == 0
        records(i).calibration_status = "calibrated";
    end
    records(i).notes = get_optional_string(T, idx, "notes");
    records(i).updated_at = get_optional_string(T, idx, "updated_at");
    records(i).platform_src_pts = parse_points(get_optional_string(T, idx, ...
        "platform_src_pts"));
    records(i).sheet_src_pts = parse_points(get_optional_string(T, idx, ...
        "sheet_src_pts"));
end
end

function refresh_gui__step_2_calibrate_platform_corners(src)
fig = ancestor(src, 'figure');
state = guidata(fig);
rec = state.records(state.index);
state.click_pts = rec.platform_src_pts;

frame = read_video_frame(rec.selected_video, state.frame_fraction, ...
    state.template);
imshow(frame, 'Parent', state.ax);
hold(state.ax, 'on');
draw_overlays(state.ax, rec.platform_src_pts, rec.sheet_src_pts);
hold(state.ax, 'off');

set(state.title_text, 'String', sprintf( ...
    '%d/%d  %s  rat%d  %s  %s', state.index, numel(state.records), ...
    rec.date_folder, rec.rat, rec.group, rec.surgery_phase));

detail = sprintf('Video:\n%s\n\nTactile:\n%s\n\nHomography:\n%s', ...
    rec.selected_video, rec.tactile_file, rec.homography_path);
set(state.detail_text, 'String', detail);
set(state.notes_edit, 'String', char(rec.notes));

next_corner = next_corner_name(size(state.click_pts, 1) + 1);
set(state.instruction_text, 'String', sprintf( ...
    'Click platform corners in order: TL, TR, BR, BL. Next: %s', ...
    next_corner));

n_done = sum([state.records.calibration_status] == "calibrated");
set(state.status_text, 'String', sprintf('%d calibrated / %d total. Current: %s', ...
    n_done, numel(state.records), rec.calibration_status));
guidata(fig, state);
end

function click_four_platform_corners(src)
state = guidata(src);
corner_names = ["Top-left", "Top-right", "Bottom-right", "Bottom-left"];
corner_colors = [1 0.2 0.2; 0.2 0.7 0.2; 0.2 0.45 1; 1 0.75 0.1];
hold(state.ax, 'on');

for k = (size(state.click_pts, 1) + 1):4
    set(state.instruction_text, 'String', sprintf( ...
        'Click %s platform corner (%d/4)', corner_names(k), k));
    axes(state.ax); %#ok<LAXES>
    [x, y] = ginput(1);
    if isempty(x)
        break;
    end
    state = guidata(src);
    state.click_pts(end+1, :) = [x y];
    guidata(src, state);
    plot(state.ax, x, y, 'o', 'MarkerSize', 9, 'LineWidth', 2, ...
        'Color', corner_colors(k, :), ...
        'MarkerFaceColor', corner_colors(k, :));
    text(state.ax, x + 8, y, corner_names(k), ...
        'Color', corner_colors(k, :), 'FontWeight', 'bold');
    drawnow;
end
hold(state.ax, 'off');

state = guidata(src);
if size(state.click_pts, 1) == 4
    rec = state.records(state.index);
    [rec.sheet_src_pts, ~] = infer_sheet_corners(state.click_pts, ...
        state.template);
    rec.platform_src_pts = state.click_pts;
    rec.calibration_status = "ready_to_save";
    rec.updated_at = string(datetime('now'));
    state.records(state.index) = rec;
    guidata(src, state);
end
refresh_gui__step_2_calibrate_platform_corners(src);
end

function state = save_current_homography(state)
rec = state.records(state.index);
[src_pts, tform] = infer_sheet_corners(state.click_pts, state.template);
rec.platform_src_pts = state.click_pts;
rec.sheet_src_pts = src_pts;
rec.homography_path = string(make_homography_path(state.output_root, rec));
rec.calibration_status = "calibrated";
rec.updated_at = string(datetime('now'));

dst_pts = state.template.dst_pts;
P_W = state.template.P_W;
P_H = state.template.P_H;
platform_src_pts = rec.platform_src_pts;
sheet_pts_in_platform = state.template.sheet_pts_in_platform;
template_source = state.template_path;
calibrated_video = rec.selected_video;
calibration_frame_transform = get_template_frame_transform(state.template);
save(char(rec.homography_path), 'tform', 'src_pts', 'dst_pts', 'P_W', ...
    'P_H', 'platform_src_pts', 'sheet_pts_in_platform', ...
    'template_source', 'calibrated_video', ...
    'calibration_frame_transform');

state.records(state.index) = rec;
end

function [src_pts, tform] = infer_sheet_corners(platform_src_pts, template)
platform_norm_pts = [0 0; 1 0; 1 1; 0 1];
norm_to_new = fitgeotrans(platform_norm_pts, platform_src_pts, 'projective');
src_pts = transformPointsForward(norm_to_new, template.sheet_pts_in_platform);
tform = fitgeotrans(src_pts, template.dst_pts, 'projective');
end

function out_path = make_homography_path(output_root, rec)
safe_name = sprintf('%s_rat%d_%s_homography.mat', ...
    sanitize_token(rec.recording_date), rec.rat, ...
    sanitize_token(video_stem(rec.selected_video)));
out_path = fullfile(output_root, safe_name);
end

function redraw_current_overlays(src)
state = guidata(src);
rec = state.records(state.index);
rec.platform_src_pts = state.click_pts;
if size(state.click_pts, 1) == 4
    [rec.sheet_src_pts, ~] = infer_sheet_corners(state.click_pts, ...
        state.template);
else
    rec.sheet_src_pts = zeros(0, 2);
end
state.records(state.index) = rec;
guidata(src, state);
refresh_gui__step_2_calibrate_platform_corners(src);
end

function clear_overlays(state)
delete_valid_graphics(state.h_markers);
delete_valid_graphics(state.h_lines);
end

function delete_valid_graphics(handles)
for i = 1:numel(handles)
    if isgraphics(handles(i))
        delete(handles(i));
    end
end
end

function draw_overlays(ax, platform_pts, sheet_pts)
corner_colors = [1 0.2 0.2; 0.2 0.7 0.2; 0.2 0.45 1; 1 0.75 0.1];
corner_names = ["TL", "TR", "BR", "BL"];

if ~isempty(platform_pts)
    for k = 1:size(platform_pts, 1)
        plot(ax, platform_pts(k, 1), platform_pts(k, 2), 'o', ...
            'MarkerSize', 9, 'LineWidth', 2, 'Color', corner_colors(k, :), ...
            'MarkerFaceColor', corner_colors(k, :));
        text(ax, platform_pts(k, 1) + 8, platform_pts(k, 2), ...
            "Platform " + corner_names(k), 'Color', corner_colors(k, :), ...
            'FontWeight', 'bold');
    end
    if size(platform_pts, 1) > 1
        plot(ax, platform_pts(:, 1), platform_pts(:, 2), 'w-', ...
            'LineWidth', 1.5);
    end
    if size(platform_pts, 1) == 4
        plot(ax, platform_pts([1:4 1], 1), platform_pts([1:4 1], 2), ...
            'w-', 'LineWidth', 1.5);
    end
end

if size(sheet_pts, 1) == 4
    plot(ax, sheet_pts([1:4 1], 1), sheet_pts([1:4 1], 2), ...
        'y-', 'LineWidth', 2);
    for k = 1:4
        plot(ax, sheet_pts(k, 1), sheet_pts(k, 2), 's', ...
            'MarkerSize', 8, 'LineWidth', 2, 'Color', 'y');
        text(ax, sheet_pts(k, 1) + 8, sheet_pts(k, 2), ...
            "Sensor " + corner_names(k), 'Color', 'y', ...
            'FontWeight', 'bold');
    end
end
end

function frame = read_video_frame(video_path, frame_fraction, template)
vr = VideoReader(char(video_path));
vr.CurrentTime = max(0, min(vr.Duration * frame_fraction, ...
    max(0, vr.Duration - 1 / vr.FrameRate)));
frame = readFrame(vr);
frame = apply_frame_transform(frame, get_template_frame_transform(template));
end

function frame = apply_frame_transform(frame, frame_transform)
switch lower(char(frame_transform))
    case 'rot180'
        frame = rot90(frame, 2);
    case {'none', 'raw'}
        % Keep raw frame orientation.
    otherwise
        error('Unknown frame transform: %s', frame_transform);
end
end

function frame_transform = get_template_frame_transform(template)
frame_transform = 'rot180';
if isfield(template, 'frame_transform') && ~isempty(template.frame_transform)
    frame_transform = template.frame_transform;
end
end

function next_uncalibrated_or_next(src)
state = guidata(src);
remaining = find([state.records.calibration_status] ~= "calibrated");
remaining = remaining(remaining > state.index);
if ~isempty(remaining)
    state.index = remaining(1);
else
    state.index = min(numel(state.records), state.index + 1);
end
state.click_pts = state.records(state.index).platform_src_pts;
guidata(src, state);
refresh_gui__step_2_calibrate_platform_corners(src);
end

function idx = first_uncalibrated_index(records)
idx = find([records.calibration_status] ~= "calibrated", 1);
if isempty(idx)
    idx = 1;
end
end

function save_records__step_2_calibrate_platform_corners(state)
T = records_to_table__step_2_calibrate_platform_corners(state.records);
writetable(T, state.calibration_path);
fprintf('Saved platform-corner calibrations: %s\n', ...
    state.calibration_path);
end

function T = records_to_table__step_2_calibrate_platform_corners(records)
T = table();
T.enabled = [records.enabled]';
T.recording_date = [records.recording_date]';
T.date_folder = [records.date_folder]';
T.rat = [records.rat]';
T.group = [records.group]';
T.surgery_phase = [records.surgery_phase]';
T.recording_folder = [records.recording_folder]';
T.tactile_file = [records.tactile_file]';
T.selected_video = [records.selected_video]';
T.platform_src_pts = arrayfun(@(r) points_to_string(r.platform_src_pts), ...
    records)';
T.sheet_src_pts = arrayfun(@(r) points_to_string(r.sheet_src_pts), ...
    records)';
T.homography_path = [records.homography_path]';
T.calibration_status = [records.calibration_status]';
T.notes = [records.notes]';
T.updated_at = [records.updated_at]';
end

function rec = empty_record__step_2_calibrate_platform_corners()
rec = struct('enabled', true, 'recording_date', "", 'date_folder', "", ...
    'rat', NaN, 'group', "", 'surgery_phase', "", ...
    'recording_folder', "", 'tactile_file', "", 'selected_video', "", ...
    'platform_src_pts', zeros(0, 2), 'sheet_src_pts', zeros(0, 2), ...
    'homography_path', "", 'calibration_status', "uncalibrated", ...
    'notes', "", 'updated_at', "");
end

function enabled = parse_enabled(values)
if islogical(values)
    enabled = values;
elseif isnumeric(values)
    enabled = values ~= 0;
else
    values = lower(strtrim(string(values)));
    enabled = values == "true" | values == "1" | values == "yes";
end
end

function value = format_recording_date(raw_value)
if isdatetime(raw_value)
    raw_value.Format = 'yyyy-MM-dd';
    value = string(raw_value);
else
    value = string(raw_value);
end
end

function value = get_optional_string(T, idx, name)
if ismember(name, string(T.Properties.VariableNames))
    value = string(T.(name)(idx));
else
    value = "";
end
if ismissing(value)
    value = "";
end
end

function text_value = points_to_string(points)
if isempty(points)
    text_value = "";
else
    text_value = string(mat2str(points, 8));
end
end

function points = parse_points(text_value)
points = zeros(0, 2);
text_value = strtrim(string(text_value));
if strlength(text_value) == 0 || ismissing(text_value)
    return;
end
try
    parsed = str2num(char(text_value)); %#ok<ST2NM>
    if size(parsed, 2) == 2
        points = parsed;
    end
catch
    points = zeros(0, 2);
end
end

function name = next_corner_name(index)
names = ["Top-left", "Top-right", "Bottom-right", "Bottom-left", ...
    "all corners clicked"];
index = min(max(index, 1), numel(names));
name = names(index);
end

function stem = video_stem(video_path)
[~, stem] = fileparts(char(video_path));
end

function token = sanitize_token(value)
token = regexprep(char(value), '[^A-Za-z0-9]+', '_');
token = regexprep(token, '^_+|_+$', '');
end

function validate_file(path_value, label)
if isempty(path_value) || ~exist(path_value, 'file')
    error('Missing %s: %s', label, path_value);
end
end

function recording_list = step_3_build_background_models_and_recordings(cfg)
%STEP_3_BUILD_BACKGROUND_MODELS_AND_RECORDINGS Finish batch inputs.
%
%   recording_list = step_3_build_background_models_and_recordings()
%   recording_list = step_3_build_background_models_and_recordings(cfg)
%
% Reads cfg.platform_calibration_path, builds one rotated background model
% per calibrated overhead video, and writes a recording list for
% s2_detect_contacts to work_root/setup/recordings.csv.

if nargin < 1 || isempty(cfg)
    cfg = gait_config();
end

validate_file(cfg.platform_calibration_path, 'platform calibration CSV');
ensure_dir(cfg.background_model_output_root);
ensure_dir(fileparts(cfg.recording_list_path));

calibrations = readtable(cfg.platform_calibration_path, ...
    'TextType', 'string', 'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');
required = ["enabled", "recording_date", "rat", "tactile_file", ...
    "selected_video", "homography_path", "calibration_status"];
for i = 1:numel(required)
    if ~ismember(required(i), string(calibrations.Properties.VariableNames))
        error('Calibration CSV is missing required column "%s".', required(i));
    end
end

enabled = parse_enabled(calibrations.enabled);
ready = enabled & calibrations.calibration_status == "calibrated" & ...
    strlength(calibrations.selected_video) > 0 & ...
    strlength(calibrations.homography_path) > 0;
calibrations = calibrations(ready, :);
if isempty(calibrations)
    error('No calibrated recordings found in %s.', cfg.platform_calibration_path);
end

template_frame_transform = read_template_frame_transform(cfg);

result_rows = cell(height(calibrations), 6);
recording_list = table();
recording_list.enabled = true(height(calibrations), 1);
recording_list.input_file = strings(height(calibrations), 1);
recording_list.camera1_path = strings(height(calibrations), 1);
recording_list.homography_path = strings(height(calibrations), 1);
recording_list.background_path = strings(height(calibrations), 1);
recording_list.output_name = strings(height(calibrations), 1);

fprintf('Building/checking %d background model(s).\n', height(calibrations));
for i = 1:height(calibrations)
    tactile_file = calibrations.tactile_file(i);
    video_path = calibrations.selected_video(i);
    homography_path = calibrations.homography_path(i);
    output_name = make_output_name(calibrations, i);
    background_path = fullfile(cfg.background_model_output_root, ...
        output_name + "_background_model.mat");

    validate_file(tactile_file, 'tactile file');
    validate_file(video_path, 'selected overhead video');
    validate_file(homography_path, 'homography');

    status = "skipped";
    message = "Existing background model";
    if cfg.overwrite_background_models || ~exist(background_path, 'file')
        fprintf('[%d/%d] BG   %s\n', i, height(calibrations), output_name);
        try
            bg_model = build_background_model(video_path, ...
                cfg.background_model_n_frames, template_frame_transform);
            save_background_model(background_path, bg_model, video_path, ...
                cfg.background_model_n_frames, template_frame_transform);
            status = "done";
            message = "OK";
        catch ME
            status = "failed";
            message = string(ME.message);
            fprintf(2, 'FAILED background model for %s: %s\n', ...
                output_name, ME.message);
        end
    else
        fprintf('[%d/%d] SKIP %s\n', i, height(calibrations), output_name);
    end

    recording_list.input_file(i) = tactile_file;
    recording_list.camera1_path(i) = video_path;
    recording_list.homography_path(i) = homography_path;
    recording_list.background_path(i) = string(background_path);
    recording_list.output_name(i) = output_name;

    result_rows(i, :) = {tactile_file, video_path, string(background_path), ...
        output_name, status, message};
end

results = cell2table(result_rows, 'VariableNames', ...
    {'input_file', 'camera1_path', 'background_path', 'output_name', ...
    'status', 'message'});
writetable(results, cfg.background_model_results_path);
writetable(recording_list, cfg.recording_list_path);

fprintf('Saved background results: %s\n', cfg.background_model_results_path);
fprintf('Saved recording list: %s\n', cfg.recording_list_path);
end

function bg_model = build_background_model(video_path, n_frames, frame_transform)
vr = VideoReader(char(video_path));
n_frames = min(n_frames, max(1, floor(vr.Duration * vr.FrameRate)));

if ~hasFrame(vr)
    error('No frames could be read from %s.', video_path);
end
first_frame = apply_frame_transform(readFrame(vr), frame_transform);
frames = zeros([size(first_frame), n_frames], 'uint8');
frames(:, :, :, 1) = first_frame;
frames_read = 1;

for k = 2:n_frames
    if ~hasFrame(vr)
        break;
    end
    frame = apply_frame_transform(readFrame(vr), frame_transform);
    frames(:, :, :, k) = frame;
    frames_read = k;
end

frames = frames(:, :, :, 1:frames_read);
bg_model = uint8(median(frames, 4));
end

function save_background_model(background_path, bg_model, video_path, ...
    n_frames, frame_transform)
source_video = video_path;
n_background_frames = n_frames;
created_at = string(datetime('now'));
save(background_path, 'bg_model', 'source_video', ...
    'n_background_frames', 'frame_transform', 'created_at');
end

function frame_transform = read_template_frame_transform(cfg)
frame_transform = 'rot180';
if isfield(cfg, 'platform_template_path') && ...
        exist(cfg.platform_template_path, 'file')
    loaded = load(cfg.platform_template_path, 'template');
    if isfield(loaded, 'template') && ...
            isfield(loaded.template, 'frame_transform') && ...
            ~isempty(loaded.template.frame_transform)
        frame_transform = loaded.template.frame_transform;
    end
end
end

function output_name = make_output_name(T, idx)
recording_date = sanitize_token__step_3_build_background_models_and_recordings(format_recording_date(T.recording_date(idx)));
rat = string(T.rat(idx));
[~, video_stem] = fileparts(char(T.selected_video(idx)));
output_name = recording_date + "_rat" + rat + "_" + ...
    sanitize_token__step_3_build_background_models_and_recordings(video_stem);
end

function token = sanitize_token__step_3_build_background_models_and_recordings(value)
token = regexprep(char(string(value)), '[^A-Za-z0-9]+', '_');
token = string(regexprep(token, '^_+|_+$', ''));
end
