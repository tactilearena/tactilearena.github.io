function [cfg, recordings] = gait_config(only)
% Paths and settings for every stage; [cfg, R] = gait_config(names) also
% returns the recording list with absolute paths.

% ---- edit these lines, or set the environment variables -----------------
data_root = getenv_or('GAIT_DATA_ROOT', fullfile(repo_root(), '..', 'gait_data'));
work_root = getenv_or('GAIT_WORK_ROOT', fullfile(repo_root(), '..', 'gait_outputs'));
annotations_root = getenv_or('GAIT_ANNOTATIONS_ROOT', fullfile(data_root, 'annotations'));
% ---------------------------------------------------------------------------

cfg = struct();
cfg.repo_root = repo_root();
cfg.data_root = char(data_root);
cfg.work_root = char(work_root);
cfg.annotations_root = char(annotations_root);
cfg.repo_data = fullfile(cfg.repo_root, 'data');

% part of the method, shipped with the repository
cfg.platform_template_path = fullfile(cfg.repo_data, 'platform_sheet_template.mat');
cfg.calibration_json = fullfile(cfg.repo_data, 'calibration_0_450', 'calibration_0_450.json');
cfg.tailbase_checkpoint = fullfile(cfg.repo_data, 'tailbase_model', 'best_tail_detector.pt');

% study annotations, from the data deposit
A = cfg.annotations_root;
cfg.recording_list_path = fullfile(A, 'recordings.csv');
cfg.homography_output_root = fullfile(A, 'homographies');
cfg.mass_path = fullfile(A, 'mass.csv');
cfg.blind_labels_dir = fullfile(A, 'blind_labels');
cfg.labeler_id = 'VL';
cfg.bout_windows_path = fullfile(A, 'mobile_bout_windows.csv');
cfg.bout_corrections_path = fullfile(A, 'cop_trajectory_corrections.csv');
cfg.corrected_contacts_path = fullfile(A, 'corrected_contacts.csv');

% pipeline outputs
cfg.background_model_output_root = fullfile(cfg.work_root, 'background_models');
cfg.dynamics_root = fullfile(cfg.work_root, 'dynamics');        % s2 detector output
cfg.cop_root = fullfile(cfg.work_root, 'cop_trajectory');       % s3 COP traces and bouts
cfg.contacts_root = fullfile(cfg.work_root, 'mobile_contacts'); % s4 labeled contacts
cfg.figure_root = fullfile(cfg.work_root, 'figures');
cfg.log_root = fullfile(cfg.work_root, 'logs');
cfg.summary_root = fullfile(cfg.work_root, 'summaries');
cfg.output_root = cfg.dynamics_root;

% s1 (new data only: video choice and corner clicks)
cfg.video_selection_path = fullfile(cfg.work_root, 'setup', 'overhead_video_selections.csv');
cfg.platform_calibration_path = fullfile(cfg.work_root, 'setup', 'platform_corner_calibrations.csv');
cfg.background_model_results_path = fullfile(cfg.work_root, 'setup', 'background_model_results.csv');
cfg.background_model_n_frames = 30;
cfg.overwrite_background_models = false;
cfg.rat_data_root = cfg.data_root;
cfg.first_recording_date = datetime(2026, 2, 11);
cfg.launch_video_picker_gui = true;
cfg.launch_platform_calibration_gui = true;

% study design
cfg.surgery_date = datetime(2026, 3, 10);
cfg.included_rats = [1 2 4 5 6];
cfg.sham_rats = [1 2];
cfg.sni_rats = [4 5 6];

% detector
cfg.detector_script = fullfile(cfg.repo_root, 'pipeline', 'peak_seed_contact_detector.m');
cfg.detector_dir = fullfile(cfg.repo_root, 'pipeline');
cfg.tailbase_script = fullfile(cfg.repo_root, 'tailbase', 'tailbase_cnn.py');
cfg.python_exe = getenv_or('GAIT_PYTHON', 'python');
cfg.overwrite = false;
cfg.require_recording_list = true;

if nargout > 1
    if nargin < 1, only = []; end
    recordings = read_recordings(cfg, only);
end
end

function r = repo_root()
r = fileparts(fileparts(mfilename('fullpath')));
end

function v = getenv_or(name, default)
v = getenv(name);
if isempty(v), v = default; end
v = char(v);
end

function T = read_recordings(cfg, only)
T = readtable(cfg.recording_list_path, 'TextType', 'string', 'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');
if ismember("enabled", string(T.Properties.VariableNames))
    e = T.enabled;
    if ~islogical(e), e = string(e) == "1" | lower(string(e)) == "true"; end
    T = T(e, :);
end
if ~isempty(only)
    T = T(ismember(T.output_name, string(only)), :);
end
T.input_file = resolve(T.input_file, cfg.data_root);
T.camera1_path = resolve(T.camera1_path, cfg.data_root);
T.homography_path = resolve(T.homography_path, cfg.homography_output_root);
T.background_path = resolve(T.background_path, cfg.background_model_output_root);
rat = extractBetween(T.output_name, "_rat", "_");
T.rat = str2double(rat(:, 1));
T.recording_date = datetime(extractBefore(T.output_name, "_rat"), 'InputFormat', 'yyyy_MM_dd');
end

function p = resolve(p, base)
p = string(p);
rel = ~(startsWith(p, ["/", "\"]) | ~cellfun(@isempty, regexp(cellstr(p), '^[A-Za-z]:[\\/]', 'once')));
p(rel) = string(fullfile(base, cellstr(p(rel))));
end
