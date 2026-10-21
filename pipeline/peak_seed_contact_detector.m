% ============================================================================
clc; close all;
% Peak-seed contact segmentation.
% This script intentionally detects only high-confidence footprint cores
% first, then relies on dynamic ROI extraction to recover IC/LO.
% s2_detect_contacts.m sets the values used in the paper, overriding the
% defaults below for MIN_CONTACT_AREA, PEAK_SEED_CANDIDATE_MODE,
% DYNAMIC_ROI_MAX_SIZE_PX and GAIT_MIN_STANCE_SEC.
if exist('SEGMENTATION_VIDEO_CAM1_PATH', 'var') && ...
        ~isempty(SEGMENTATION_VIDEO_CAM1_PATH)
    video_cam1_path = SEGMENTATION_VIDEO_CAM1_PATH;
else
    video_cam1_path = '../data/camera_1_20260211_203112.mp4';
end
homography_path   = 'homography.mat';
background_path   = 'background_model.mat';
if exist('SEGMENTATION_HOMOGRAPHY_PATH', 'var') && ...
        ~isempty(SEGMENTATION_HOMOGRAPHY_PATH)
    homography_path = char(SEGMENTATION_HOMOGRAPHY_PATH);
end
if exist('SEGMENTATION_BACKGROUND_PATH', 'var') && ...
        ~isempty(SEGMENTATION_BACKGROUND_PATH)
    background_path = char(SEGMENTATION_BACKGROUND_PATH);
end
if exist('SEGMENTATION_SAVE_VIDEO', 'var') && ~isempty(SEGMENTATION_SAVE_VIDEO)
    SAVE_SEGMENTATION_VIDEO = logical(SEGMENTATION_SAVE_VIDEO);
else
    SAVE_SEGMENTATION_VIDEO = true;
end
if exist('SEGMENTATION_SHOW_FIGURE', 'var') && ~isempty(SEGMENTATION_SHOW_FIGURE)
    SHOW_SEGMENTATION_FIGURE = logical(SEGMENTATION_SHOW_FIGURE);
else
    SHOW_SEGMENTATION_FIGURE = true;
end
SEGMENTATION_VIDEO_FPS  = 30;
if exist('SEGMENTATION_VIDEO_SAMPLE_FPS_OVERRIDE', 'var') && ...
        ~isempty(SEGMENTATION_VIDEO_SAMPLE_FPS_OVERRIDE)
    SEGMENTATION_VIDEO_SAMPLE_FPS = SEGMENTATION_VIDEO_SAMPLE_FPS_OVERRIDE;
else
    SEGMENTATION_VIDEO_SAMPLE_FPS = 30; % output sampling in experiment-time
end
                                    % seconds, not pressure-frame index
DEBUG_FOOTPRINT_CANDIDATES = true; % show rejected footprint candidates
MAX_DEBUG_CANDIDATES = 64;
REJECT_TAILBASE_CONTACTS = false; % off in the analysis; the tail proxy can
                                  % incorrectly reject true paw contacts
PRINT_RAW_CLUSTER_SUMMARY = false; % raw pre-grouping fragments are noisy;
                                   % keep the full dump opt-in for debugging

layout            = 'runway';
if exist('SEGMENTATION_LAYOUT', 'var') && ~isempty(SEGMENTATION_LAYOUT)
    layout = char(SEGMENTATION_LAYOUT);
end
PRESCAN_SAMPLE_FPS = Inf;
if strcmp(layout, 'square')
    PRESCAN_SAMPLE_FPS = 30;
end
MAX_TIME_SEC = Inf;
if exist('SEGMENTATION_MAX_TIME_SEC', 'var') && ...
        ~isempty(SEGMENTATION_MAX_TIME_SEC)
    MAX_TIME_SEC = double(SEGMENTATION_MAX_TIME_SEC);
end
if exist('SEGMENTATION_PRESCAN_SAMPLE_FPS', 'var') && ...
        ~isempty(SEGMENTATION_PRESCAN_SAMPLE_FPS)
    PRESCAN_SAMPLE_FPS = double(SEGMENTATION_PRESCAN_SAMPLE_FPS);
end
if exist('SEGMENTATION_DEBUG_FOOTPRINT_CANDIDATES', 'var') && ...
        ~isempty(SEGMENTATION_DEBUG_FOOTPRINT_CANDIDATES)
    DEBUG_FOOTPRINT_CANDIDATES = logical(SEGMENTATION_DEBUG_FOOTPRINT_CANDIDATES);
end
if exist('SEGMENTATION_PRINT_RAW_CLUSTER_SUMMARY', 'var') && ...
        ~isempty(SEGMENTATION_PRINT_RAW_CLUSTER_SUMMARY)
    PRINT_RAW_CLUSTER_SUMMARY = logical(SEGMENTATION_PRINT_RAW_CLUSTER_SUMMARY);
end
playback_speed    = 1.0;
if exist('SEGMENTATION_PLAYBACK_SPEED', 'var') && ...
        ~isempty(SEGMENTATION_PLAYBACK_SPEED)
    playback_speed = double(SEGMENTATION_PLAYBACK_SPEED);
end
board_size        = 64;
max_board_id      = 4;
USE_VECTOR_PRESSURE_ASSEMBLY = true;
if exist('SEGMENTATION_USE_VECTOR_PRESSURE_ASSEMBLY', 'var') && ...
        ~isempty(SEGMENTATION_USE_VECTOR_PRESSURE_ASSEMBLY)
    USE_VECTOR_PRESSURE_ASSEMBLY = logical(SEGMENTATION_USE_VECTOR_PRESSURE_ASSEMBLY);
end
switch layout
    case 'square'
        P_W = 128;
        P_H = 128;
    otherwise
        P_W = 256;
        P_H = 64;
end
if exist('SEGMENTATION_PRESSURE_WIDTH', 'var') && ...
        ~isempty(SEGMENTATION_PRESSURE_WIDTH)
    P_W = double(SEGMENTATION_PRESSURE_WIDTH);
end
if exist('SEGMENTATION_PRESSURE_HEIGHT', 'var') && ...
        ~isempty(SEGMENTATION_PRESSURE_HEIGHT)
    P_H = double(SEGMENTATION_PRESSURE_HEIGHT);
end
bg_diff_thresh    = 100;
min_blob_area     = 27903;

% ------ Quadrant/body-axis stabilization ------------------------------
% The axis direction is estimated without angular smoothing. A short
% hysteresis window suppresses one-frame 180-degree flips but allows a
% sustained reversal.
tail_centroid_min_dist_px = 12;
axis_flip_confirm_sec = 0.25;
offset_smooth_alpha = 0.7;
edge_margin_px      = 15;
body_clip_margin_px = 2;     % visual/debug flag for projected body
                             % touching tactile FOV edge
body_edge_contact_frac_max = 0.12; % tolerate mild clipping; only reject
                                   % quadrant splits when the body is
                                   % substantially outside the FOV
standing_area_frac  = .5;
fb_split_target     = 0.3;

% ------ Footstep tracking ---------------------------------------------
EXPORT_FOOTSTEP_DYNAMICS = true;
PRESSURE_THRESH     = 200;    % tactile counts above this = contact
MIN_CONTACT_AREA    = 10;     % peak-seed area: require a confident
                              % footprint core before opening/tracking a
                              % candidate step. Dynamic extraction later
                              % recovers lower-pressure IC/LO tails.
if exist('SEGMENTATION_MIN_CONTACT_AREA', 'var') && ...
        ~isempty(SEGMENTATION_MIN_CONTACT_AREA)
    MIN_CONTACT_AREA = double(SEGMENTATION_MIN_CONTACT_AREA);
end
PRELABEL_MERGE_DIST_PX = 8;   % centroid-distance fallback for merging
                              % nearby same-frame pressure islands
PRELABEL_MERGE_EDGE_GAP_PX = 6; % primary same-paw fragment merge: nearest
                               % active pixels can be close even when
                               % centroids are far apart
PRELABEL_MERGE_DILATE_RADIUS_PX = 4; % equivalent visual rule: dilate each
                                    % component and merge if dilated masks
                                    % touch/overlap
PRELABEL_MERGE_MAX_AREA = 120; % do not merge into implausibly large paw
PRELABEL_MERGE_SEAM_MAX_AREA = 240; % board-boundary fragments can be larger
                                    % because a single paw is split by the
                                    % stitched-board seam
PRELABEL_MERGE_DEBUG = false;
PRELABEL_MERGE_DEBUG_FRAME_START = -Inf;
PRELABEL_MERGE_DEBUG_FRAME_END = Inf;
PRELABEL_SPLIT_MULTIPEAK = false;
PRELABEL_SPLIT_MIN_AREA = 20;
PRELABEL_SPLIT_MIN_PEAK_DIST_PX = 5;
PRELABEL_SPLIT_MIN_PROMINENCE = 500;
OPEN_CLUSTER_MERGE_DIST_PX = 8; % merge duplicate open clusters on same paw
FLIP_FORE_LATERAL_LABELS = false; % diagnostic option: invert only FL/FR rank
                                  % mapping when validating camera anatomy
PROXIMAL_NEW_CONTACT_PX = 6; % if a later seed shifts this far proximally
                             % from an existing cluster, open a new event
                             % instead of letting the two contacts compete
PEAK_SEED_MIN_DENSITY = 0.35; % area / bbox area; tail-base contacts are
                              % often sparse and should be rejected
PEAK_SEED_MIN_MEAN_PRESSURE = 350; % reject diffuse low-pressure contacts
PEAK_SEED_CANDIDATE_MODE = 'strict'; % strict = density+mean pressure gate;
                                     % binary = area after threshold only
TAILBASE_REJECT_RADIUS_PX = 18; % reject seed candidates close to tail base
TAILBASE_REJECT_BEHIND_FRAC = 0.20; % reject candidates this far behind body
                                    % centroid along head axis
TAILBASE_REJECT_MIDLINE_PX = 12; % behind-body rejection only near midline,
                                % so true laterally placed hind paws survive
if strcmp(layout, 'square')
    PEAK_SEED_CANDIDATE_MODE = 'binary';
    PRELABEL_SPLIT_MULTIPEAK = true;
end
if exist('SEGMENTATION_PEAK_SEED_CANDIDATE_MODE', 'var') && ...
        ~isempty(SEGMENTATION_PEAK_SEED_CANDIDATE_MODE)
    PEAK_SEED_CANDIDATE_MODE = char(SEGMENTATION_PEAK_SEED_CANDIDATE_MODE);
end
if exist('SEGMENTATION_PRELABEL_MERGE_DIST_PX', 'var') && ...
        ~isempty(SEGMENTATION_PRELABEL_MERGE_DIST_PX)
    PRELABEL_MERGE_DIST_PX = double(SEGMENTATION_PRELABEL_MERGE_DIST_PX);
end
if exist('SEGMENTATION_PRELABEL_MERGE_EDGE_GAP_PX', 'var') && ...
        ~isempty(SEGMENTATION_PRELABEL_MERGE_EDGE_GAP_PX)
    PRELABEL_MERGE_EDGE_GAP_PX = ...
        double(SEGMENTATION_PRELABEL_MERGE_EDGE_GAP_PX);
end
if exist('SEGMENTATION_PRELABEL_MERGE_DILATE_RADIUS_PX', 'var') && ...
        ~isempty(SEGMENTATION_PRELABEL_MERGE_DILATE_RADIUS_PX)
    PRELABEL_MERGE_DILATE_RADIUS_PX = ...
        double(SEGMENTATION_PRELABEL_MERGE_DILATE_RADIUS_PX);
end
if exist('SEGMENTATION_PRELABEL_MERGE_MAX_AREA', 'var') && ...
        ~isempty(SEGMENTATION_PRELABEL_MERGE_MAX_AREA)
    PRELABEL_MERGE_MAX_AREA = double(SEGMENTATION_PRELABEL_MERGE_MAX_AREA);
end
if exist('SEGMENTATION_PRELABEL_MERGE_SEAM_MAX_AREA', 'var') && ...
        ~isempty(SEGMENTATION_PRELABEL_MERGE_SEAM_MAX_AREA)
    PRELABEL_MERGE_SEAM_MAX_AREA = ...
        double(SEGMENTATION_PRELABEL_MERGE_SEAM_MAX_AREA);
end
if exist('SEGMENTATION_PRELABEL_MERGE_DEBUG', 'var') && ...
        ~isempty(SEGMENTATION_PRELABEL_MERGE_DEBUG)
    PRELABEL_MERGE_DEBUG = logical(SEGMENTATION_PRELABEL_MERGE_DEBUG);
end
if exist('SEGMENTATION_PRELABEL_MERGE_DEBUG_FRAME_START', 'var') && ...
        ~isempty(SEGMENTATION_PRELABEL_MERGE_DEBUG_FRAME_START)
    PRELABEL_MERGE_DEBUG_FRAME_START = ...
        double(SEGMENTATION_PRELABEL_MERGE_DEBUG_FRAME_START);
end
if exist('SEGMENTATION_PRELABEL_MERGE_DEBUG_FRAME_END', 'var') && ...
        ~isempty(SEGMENTATION_PRELABEL_MERGE_DEBUG_FRAME_END)
    PRELABEL_MERGE_DEBUG_FRAME_END = ...
        double(SEGMENTATION_PRELABEL_MERGE_DEBUG_FRAME_END);
end
if exist('SEGMENTATION_OPEN_CLUSTER_MERGE_DIST_PX', 'var') && ...
        ~isempty(SEGMENTATION_OPEN_CLUSTER_MERGE_DIST_PX)
    OPEN_CLUSTER_MERGE_DIST_PX = ...
        double(SEGMENTATION_OPEN_CLUSTER_MERGE_DIST_PX);
end
if exist('SEGMENTATION_FLIP_FORE_LATERAL_LABELS', 'var') && ...
        ~isempty(SEGMENTATION_FLIP_FORE_LATERAL_LABELS)
    FLIP_FORE_LATERAL_LABELS = ...
        logical(SEGMENTATION_FLIP_FORE_LATERAL_LABELS);
end
CLUSTER_DIST_PX     = 10;     % centroid search radius for frame linking
CLUSTER_MAX_DRIFT_PX = 12;    % max centroid drift from initial contact
                               % allowed within one footstep cluster
CLUSTER_GAP_FRAMES  = 3;      % frames of absence before liftoff declared
DISPLAY_CLOSED_LABELS = false; % debug display should reflect the current
                               % pressure frame, not recently closed steps
DISPLAY_LINGER_FRAMES = 0;     % only used if DISPLAY_CLOSED_LABELS = true
SWING_MIN_SEC         = 0.10; % minimum swing phase: seconds that must
                               % elapse between liftoff of a label and
                               % its next initial contact. If a new IC
                               % would violate this, that label is
                               % forbidden and the next-best quadrant
                               % is tried instead.
TACTILE_MM_PER_PX      = 2;    % tactile board scale
GAIT_MERGE_MAX_DIST_MM = 30;   % max centroid shift for merging split
                               % same-paw contacts across a short gap
GAIT_MERGE_MAX_DIST_PX = GAIT_MERGE_MAX_DIST_MM / TACTILE_MM_PER_PX;
GAIT_MIN_STANCE_SEC    = 0.20; % reject plotted stance events shorter
                               % than this duration
PRE_REFINEMENT_GROUP_ENABLED = true;
PRE_REFINEMENT_GROUP_MAX_GAP_SEC = SWING_MIN_SEC;
PRE_REFINEMENT_GROUP_MAX_DIST_PX = GAIT_MERGE_MAX_DIST_PX;
PRE_REFINEMENT_CROSS_LABEL_DIST_PX = 5;
% Prevent transitive fragment chaining from turning repeated footfalls at
% one location into a many-second "single" cluster.
PRE_REFINEMENT_GROUP_MAX_SPAN_SEC = 1.0;
FINAL_ASSIGN_MAX_DIST_PX = 30;
if exist('SEGMENTATION_SWING_MIN_SEC', 'var') && ...
        ~isempty(SEGMENTATION_SWING_MIN_SEC)
    SWING_MIN_SEC = double(SEGMENTATION_SWING_MIN_SEC);
    PRE_REFINEMENT_GROUP_MAX_GAP_SEC = SWING_MIN_SEC;
end
if exist('SEGMENTATION_GAIT_MERGE_MAX_DIST_PX', 'var') && ...
        ~isempty(SEGMENTATION_GAIT_MERGE_MAX_DIST_PX)
    GAIT_MERGE_MAX_DIST_PX = double(SEGMENTATION_GAIT_MERGE_MAX_DIST_PX);
    GAIT_MERGE_MAX_DIST_MM = GAIT_MERGE_MAX_DIST_PX * TACTILE_MM_PER_PX;
elseif exist('SEGMENTATION_GAIT_MERGE_MAX_DIST_MM', 'var') && ...
        ~isempty(SEGMENTATION_GAIT_MERGE_MAX_DIST_MM)
    GAIT_MERGE_MAX_DIST_MM = double(SEGMENTATION_GAIT_MERGE_MAX_DIST_MM);
    GAIT_MERGE_MAX_DIST_PX = GAIT_MERGE_MAX_DIST_MM / TACTILE_MM_PER_PX;
end
if exist('SEGMENTATION_GAIT_MIN_STANCE_SEC', 'var') && ...
        ~isempty(SEGMENTATION_GAIT_MIN_STANCE_SEC)
    GAIT_MIN_STANCE_SEC = double(SEGMENTATION_GAIT_MIN_STANCE_SEC);
end
if exist('SEGMENTATION_PRE_REFINEMENT_GROUP_ENABLED', 'var') && ...
        ~isempty(SEGMENTATION_PRE_REFINEMENT_GROUP_ENABLED)
    PRE_REFINEMENT_GROUP_ENABLED = logical(SEGMENTATION_PRE_REFINEMENT_GROUP_ENABLED);
end
if exist('SEGMENTATION_PRE_REFINEMENT_GROUP_MAX_GAP_SEC', 'var') && ...
        ~isempty(SEGMENTATION_PRE_REFINEMENT_GROUP_MAX_GAP_SEC)
    PRE_REFINEMENT_GROUP_MAX_GAP_SEC = ...
        double(SEGMENTATION_PRE_REFINEMENT_GROUP_MAX_GAP_SEC);
end
if exist('SEGMENTATION_PRE_REFINEMENT_GROUP_MAX_DIST_PX', 'var') && ...
        ~isempty(SEGMENTATION_PRE_REFINEMENT_GROUP_MAX_DIST_PX)
    PRE_REFINEMENT_GROUP_MAX_DIST_PX = ...
        double(SEGMENTATION_PRE_REFINEMENT_GROUP_MAX_DIST_PX);
end
if exist('SEGMENTATION_PRE_REFINEMENT_CROSS_LABEL_DIST_PX', 'var') && ...
        ~isempty(SEGMENTATION_PRE_REFINEMENT_CROSS_LABEL_DIST_PX)
    PRE_REFINEMENT_CROSS_LABEL_DIST_PX = ...
        double(SEGMENTATION_PRE_REFINEMENT_CROSS_LABEL_DIST_PX);
end
if exist('SEGMENTATION_FINAL_ASSIGN_MAX_DIST_PX', 'var') && ...
        ~isempty(SEGMENTATION_FINAL_ASSIGN_MAX_DIST_PX)
    FINAL_ASSIGN_MAX_DIST_PX = double(SEGMENTATION_FINAL_ASSIGN_MAX_DIST_PX);
end
DYNAMIC_PEAK_FRACTION  = 0.05; % refined IC/LO = sustained crossing of
                               % this fraction of peak ROI total pressure
DYNAMIC_SEARCH_MAX_SEC  = 2; % bounded search around detected contact
DYNAMIC_ROI_PAD_PX      = 3;    % padding around detected footprint bbox
DYNAMIC_ROI_MAX_SIZE_PX = 15;   % max dynamic ROI width/height. Square
                                % standing/turning contacts need a larger
                                % union bbox than runway paw rolls.
if strcmp(layout, 'square')
    DYNAMIC_ROI_MAX_SIZE_PX = 32;
end
if exist('SEGMENTATION_DYNAMIC_ROI_MAX_SIZE_PX', 'var') && ...
        ~isempty(SEGMENTATION_DYNAMIC_ROI_MAX_SIZE_PX)
    DYNAMIC_ROI_MAX_SIZE_PX = double(SEGMENTATION_DYNAMIC_ROI_MAX_SIZE_PX);
end
DYNAMIC_SMOOTH_FRAMES   = 5;    % moving median/mean window for ROI trace
DYNAMIC_MIN_ON_FRAMES   = 3;    % sustained frames above DYNAMIC_PEAK_FRACTION of peak
DYNAMIC_OFF_FRAMES      = 5;    % sustained frames below DYNAMIC_PEAK_FRACTION of peak for IC/LO
DYNAMIC_STD_GROWTH_FACTOR = 2.5; % terminate if spatial spread gets much
                                % larger than spread at peak pressure
DYNAMIC_STD_GROWTH_MIN_PX = 3;   % absolute spread increase required too
DYNAMIC_CENTROID_DRIFT_MAX_PX = 6; % terminate refined dynamics if ROI
                                  % pressure centroid moves this far from
                                  % the peak footprint centroid
DYNAMIC_SPLIT_VALLEY_FRACTION = 0.35; % split if inter-peak valley drops
                                      % below this fraction of the smaller peak
DYNAMIC_SPLIT_MIN_PEAK_FRACTION = 0.50; % second peak must be at least this
                                       % fraction of the event peak
DYNAMIC_SPLIT_CENTROID_JUMP_PX = 8; % centroid shift required across valley
DYNAMIC_GLOBAL_DROPOUT_FRACTION = 0.02; % ignore valleys where whole-board
                                       % pressure also disappears
DYNAMIC_COMPONENT_MIN_AREA_PX = 3; % min connected-component area to track
DYNAMIC_COMPONENT_OVERLAP_DILATE_PX = 1; % tolerate tiny frame-to-frame
                                         % component boundary jitter, but
                                         % do not jump to a nearby component
DYNAMIC_COMPONENT_MERGE_AREA_FACTOR = 2.0; % terminate if a tracked component
                                          % suddenly becomes much larger,
                                          % consistent with merging into a
                                          % neighboring paw

% The CoP is the pressure-weighted centroid of the entire tactile map.
% Its speed, smoothed over COP_VEL_WINDOW frames, tells us whether the
% rat is moving or stationary.
COP_VEL_WINDOW        = 200;  % frames to smooth CoP displacement
COP_MOVING_THRESH_PX_S = 200; % tactile px/s above which = locomoting

IC_MIN_OVERLAP_PX   = 5;    

HIND_FB_THRESH      = 0.0;    % 0 = blob strictly behind body centroid
                               % qualifies. Raise to e.g. 0.1 to require
                               % blobs 10% of half_len behind centroid.

HIND_EDGE_MARGIN_PX = 30;     % tactile px from left or right edge
HIND_PAIR_MAX_DIST_MM = 20;   % max distance between two contacts for the
                               % special HINDx2 override. 20 mm = 10 px
                               % on the 2 mm/px tactile grid.
HIND_PAIR_MAX_DIST_PX = HIND_PAIR_MAX_DIST_MM / TACTILE_MM_PER_PX;
SAME_GIRDLE_PAIR_MAX_FB_SEP_MM = 24; % FL/FR or HL/HR can be laterally
                                     % separated, but should be similar
                                     % along the body front/back axis
SAME_GIRDLE_PAIR_MAX_FB_SEP_PX = ...
    SAME_GIRDLE_PAIR_MAX_FB_SEP_MM / TACTILE_MM_PER_PX;

% LOAD DATA
if exist('SEGMENTATION_INPUT_FILE', 'var') && ~isempty(SEGMENTATION_INPUT_FILE)
    input_path = char(SEGMENTATION_INPUT_FILE);
    [fpath, filename, ext] = fileparts(input_path);
    filename = [filename ext];
    if isempty(fpath), fpath = pwd; end
else
    [filename, fpath] = uigetfile('*.mat', 'Select tactile data file');
    if filename == 0, return; end
end
data = load(fullfile(fpath, filename));
fprintf('Loaded: %s\n', filename);

if exist('SEGMENTATION_OUTPUT_DIR', 'var') && ~isempty(SEGMENTATION_OUTPUT_DIR)
    output_dir = char(SEGMENTATION_OUTPUT_DIR);
else
    output_dir = fpath;
end
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
tailbase_predictions_path = fullfile(output_dir, 'square_tailbase_predictions.csv');
if exist('SEGMENTATION_TAILBASE_PREDICTIONS_PATH', 'var') && ...
        ~isempty(SEGMENTATION_TAILBASE_PREDICTIONS_PATH)
    tailbase_predictions_path = char(SEGMENTATION_TAILBASE_PREDICTIONS_PATH);
end
tailbase_predictions = load_tailbase_predictions(tailbase_predictions_path);

cam1   = VideoReader(video_cam1_path);
tscam1 = data.camera1_frame_timestamps;
axis_flip_confirm_frames = max(1, round(axis_flip_confirm_sec * cam1.FrameRate));

if ~exist(homography_path,'file') || ~exist(background_path,'file')
    error('homography.mat or background_model.mat not found.');
end
hom     = load(homography_path);  tform    = hom.tform;
bg      = load(background_path);  bg_model = bg.bg_model;
bg_gray = rgb2gray(bg_model);
fprintf('Homography and background model loaded.\n');

% BOARDS & TIMESTAMPS
all_board_names = {'Board1','Board2','Board3','Board4'};
board_names = {};
for i = 1:numel(all_board_names)
    if isfield(data, [all_board_names{i} '_timestamps'])
        board_names{end+1} = all_board_names{i};
    end
end
if isempty(board_names), error('No BoardN_* variables found.'); end

t_start_cands = [tscam1(1)];
board_ts_norm = struct();
for i = 1:numel(board_names)
    ts = data.([board_names{i} '_timestamps']);
    if iscell(ts), ts = cell2mat(ts); end
    ts = ts(:);
    board_ts_norm.(board_names{i}) = ts;
    t_start_cands(end+1) = ts(1);
end

t0       = min(t_start_cands);
tscam1_n = tscam1 - t0;
for i = 1:numel(board_names)
    board_ts_norm.(board_names{i}) = board_ts_norm.(board_names{i}) - t0;
end

switch layout
    case 'runway'
        grid_rows = 1; grid_cols = 4;
        layout_board_ids = [4 3 2 1];
        transforms_by_id = {'none','none','none','none'};
    case 'square'
        grid_rows = 2; grid_cols = 2;
        layout_board_ids = [1 2 3 4];
        transforms_by_id = {'rot90','none','rot180','rot270'};
    otherwise, error('Unknown layout "%s"', layout);
end
if exist('SEGMENTATION_LAYOUT_BOARD_IDS', 'var') && ...
        ~isempty(SEGMENTATION_LAYOUT_BOARD_IDS)
    layout_board_ids = double(SEGMENTATION_LAYOUT_BOARD_IDS);
end
if exist('SEGMENTATION_TRANSFORMS_BY_ID', 'var') && ...
        ~isempty(SEGMENTATION_TRANSFORMS_BY_ID)
    transforms_by_id = SEGMENTATION_TRANSFORMS_BY_ID;
end

all_ts_cells = {tscam1_n(:)};
for i = 1:numel(board_names)
    all_ts_cells{end+1} = board_ts_norm.(board_names{i})(:);
end
all_times = unique(sort(vertcat(all_ts_cells{:})));
if isfinite(MAX_TIME_SEC)
    all_times = all_times(all_times <= MAX_TIME_SEC);
end
if length(all_times) > 10000
    all_times = all_times(1:ceil(length(all_times)/10000):end);
end
n_frames = length(all_times);

ref_board_ts = board_ts_norm.(board_names{1});
if numel(ref_board_ts) > 1
    tac_fps = numel(ref_board_ts) / ref_board_ts(end);
else
    tac_fps = numel(all_times) / all_times(end);
end
fprintf('Tactile frame rate: %.1f fps (from %s)\n', tac_fps, board_names{1});

% PRE-SCAN: global max camera mask area
if isfinite(PRESCAN_SAMPLE_FPS) && PRESCAN_SAMPLE_FPS > 0
    fprintf('Pre-scan: finding global max mask area at %.1f camera fps...\n', ...
        PRESCAN_SAMPLE_FPS);
else
    fprintf('Pre-scan: finding global max mask area from every camera frame...\n');
end
cam1_prescan  = VideoReader(video_cam1_path);
n_cam1        = min(cam1_prescan.NumFrames, length(tscam1));
max_mask_area = 0;
last_prescan_time = -Inf;
for ci = 1:n_cam1
    if ~hasFrame(cam1_prescan), break; end
    frame    = rot90(readFrame(cam1_prescan), 2);
    if isfinite(PRESCAN_SAMPLE_FPS) && PRESCAN_SAMPLE_FPS > 0
        frame_time = double(tscam1(min(ci, numel(tscam1))));
        if frame_time - last_prescan_time < (1 / PRESCAN_SAMPLE_FPS)
            continue;
        end
        last_prescan_time = frame_time;
    end
    diff_img = abs(double(rgb2gray(frame)) - double(bg_gray));
    mask     = diff_img > bg_diff_thresh;
    mask     = imclose(mask, strel('disk',4));
    mask     = imopen(mask,  strel('disk',3));
    mask     = imfill(mask,  'holes');
    cc       = bwconncomp(mask);
    props    = regionprops(cc,'Area');
    for kb = 1:numel(props)
        if props(kb).Area > max_mask_area, max_mask_area = props(kb).Area; end
    end
end
standing_threshold = standing_area_frac * max_mask_area;
fprintf('Global max mask area: %d px  |  Standing threshold: %d px\n', ...
    max_mask_area, round(standing_threshold));

% =======================================================================
% FIGURE
% =======================================================================
if SHOW_SEGMENTATION_FIGURE
    figure_visible = 'on';
else
    figure_visible = 'off';
end
UPDATE_SEGMENTATION_DISPLAY = SHOW_SEGMENTATION_FIGURE || SAVE_SEGMENTATION_VIDEO;
f = figure('Position',[50 50 1400 500], ...
    'Name','Contact detector', 'Visible', figure_visible);
seg_video_writer = [];
seg_video_path = '';
seg_video_frame_count = 0;
seg_video_next_time = -Inf;
seg_video_sample_dt = 1 / SEGMENTATION_VIDEO_SAMPLE_FPS;
if SAVE_SEGMENTATION_VIDEO
    [~, base_name] = fileparts(filename);
    seg_video_path = fullfile(output_dir, sprintf('%s_peak_seed_segmentation_labeled.mp4', base_name));
    seg_video_writer = VideoWriter(seg_video_path, 'MPEG-4');
    seg_video_writer.FrameRate = SEGMENTATION_VIDEO_FPS;
    open(seg_video_writer);
    setappdata(f, 'cleanup_video_writer', onCleanup(@() close_video_writer(seg_video_writer)));
end

ctrl_panel = uipanel(f,'Units','pixels','Position',[0 0 1400 52], ...
    'BackgroundColor',[0.15 0.15 0.15],'BorderType','none');
ctrl_state.is_paused      = false;
ctrl_state.playback_speed = playback_speed;
set(ctrl_panel,'UserData',ctrl_state);

uicontrol(ctrl_panel,'Style','pushbutton','String','Pause', ...
    'Units','pixels','Position',[10 8 100 36], ...
    'FontSize',11,'FontWeight','bold', ...
    'BackgroundColor',[0.3 0.3 0.3],'ForegroundColor',[1 1 1], ...
    'Callback',@cb_pause);

speed_vals = [0.25, 0.5, 1.0, 2.0, 4.0];
speed_lbls = {'<< 0.25x','< 0.5x','1x','2x >','4x >>'};
speed_x    = [130, 218, 296, 364, 442];
speed_w    = [ 80,  70,  60,  70,  80];
h_speed_btns = gobjects(1,numel(speed_vals));
for si = 1:numel(speed_vals)
    h_speed_btns(si) = uicontrol(ctrl_panel,'Style','pushbutton', ...
        'String',speed_lbls{si},'Units','pixels', ...
        'Position',[speed_x(si) 8 speed_w(si) 36], ...
        'FontSize',10,'FontWeight','bold', ...
        'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.8 0.8 0.8], ...
        'UserData',speed_vals(si),'Callback',@cb_speed);
end
highlight_speed_btn(h_speed_btns, speed_vals, playback_speed);

h_status = uicontrol(ctrl_panel,'Style','text','String','Starting...', ...
    'Units','pixels','Position',[540 10 600 28], ...
    'FontSize',10,'HorizontalAlignment','left', ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor',[1 0.8 0.2]);

ax_tac = axes(f,'Units','normalized','Position',[0.02 0.12 0.65 0.83]);
h_tac  = imagesc(ax_tac, zeros(P_H,P_W));
clim(ax_tac,[0 4096]); colormap(ax_tac,'hot'); colorbar(ax_tac);
axis(ax_tac,'off');
set(ax_tac,'DataAspectRatioMode','manual','DataAspectRatio',[1 1 1], ...
    'PlotBoxAspectRatioMode','manual','PlotBoxAspectRatio',[P_W P_H 1], ...
    'XLim',[0.5 P_W+0.5],'YLim',[0.5 P_H+0.5], ...
    'XLimMode','manual','YLimMode','manual');
hold(ax_tac,'on');

quad_colors = {[0.2 1.0 0.2],[1.0 0.6 0.1],[0.3 0.7 1.0],[1.0 0.9 0.2]};
h_quads = gobjects(4,1);
for qi = 1:4
    h_quads(qi) = patch(ax_tac,NaN,NaN,quad_colors{qi}, ...
        'FaceAlpha',0.25,'EdgeColor','none');
end

h_outline    = plot(ax_tac,NaN,NaN,'w-','LineWidth',1.5);
h_axis_line  = plot(ax_tac,NaN,NaN,'y-','LineWidth',2.0);
h_centroid   = plot(ax_tac,NaN,NaN,'w+','MarkerSize',10,'LineWidth',2);
h_tail_tip   = plot(ax_tac,NaN,NaN,'co','MarkerSize',10,'LineWidth',2.5);
h_head_arrow = quiver(ax_tac,NaN,NaN,NaN,NaN,0, ...
    'Color',[1 0 1],'LineWidth',2.5,'MaxHeadSize',0.4);

h_standing_txt = text(ax_tac,P_W/2,P_H/2,'', ...
    'FontSize',13,'FontWeight','bold','Color',[1 0.3 0.3], ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Visible','off');
h_edge_txt = text(ax_tac,P_W/2,10,'', ...
    'FontSize',11,'FontWeight','bold','Color',[1 0.8 0], ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Visible','off');
h_hind_txt = text(ax_tac,P_W/2,P_H-6,'', ...
    'FontSize',10,'FontWeight','bold','Color',[0.9 0.5 1.0], ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Visible','off');

h_title = title(ax_tac,'Initialising...');

ax_c1 = axes(f,'Units','normalized','Position',[0.70 0.12 0.28 0.83]);
h_c1  = imshow(rot90(readFrame(cam1),2),'Parent',ax_c1);
title(ax_c1,'Camera 1');

MAX_LABEL_HANDLES = 32;
h_fp_labels  = gobjects(MAX_LABEL_HANDLES,1);
label_names  = {'FL','FR','HL','HR'};
label_colors = {[0.2 1.0 0.2],[1.0 0.6 0.1],[0.3 0.7 1.0],[1.0 0.9 0.2]};
for hi = 1:MAX_LABEL_HANDLES
    h_fp_labels(hi) = text(ax_tac, NaN, NaN, '', ...
        'FontSize',12,'FontWeight','bold','Color',[1 1 1], ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'BackgroundColor',[0 0 0 0.55],'Margin',2,'Visible','off');
end
h_reject_marks = gobjects(MAX_DEBUG_CANDIDATES,1);
h_reject_text = gobjects(MAX_DEBUG_CANDIDATES,1);
for hi = 1:MAX_DEBUG_CANDIDATES
    h_reject_marks(hi) = plot(ax_tac, NaN, NaN, 'rx', ...
        'MarkerSize', 8, 'LineWidth', 1.5, 'Visible', 'off');
    h_reject_text(hi) = text(ax_tac, NaN, NaN, '', ...
        'FontSize', 7, 'FontWeight', 'bold', 'Color', [1 0.1 0.1], ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
        'Visible', 'off');
end

% STATE
tidx_by_board    = ones(1,max_board_id);
board_imgs_by_id = cell(1,max_board_id);
for id = 1:max_board_id, board_imgs_by_id{id} = zeros(board_size); end
combined   = zeros(P_H,P_W);
raw_frame1 = [];

smooth_offset = NaN;
previous_axis_x = NaN;
previous_axis_y = NaN;
pending_flip_x = NaN;
pending_flip_y = NaN;
pending_flip_count = 0;
last_axis_frame = NaN;

cam_frame_count = 0;

last_outline_x = NaN; last_outline_y = NaN;
last_axis_x    = NaN; last_axis_y    = NaN;
last_cx        = NaN; last_cy        = NaN;
last_tail_x    = NaN; last_tail_y    = NaN;
last_arrow_ox  = NaN; last_arrow_oy  = NaN;
last_arrow_ux  = NaN; last_arrow_uy  = NaN;
last_quad_bx   = {NaN,NaN,NaN,NaN};
last_quad_by   = {NaN,NaN,NaN,NaN};
last_quad_masks    = {[],[],[],[]};
last_quad_assigned = false;

% Geometry snapshot used by heuristics — updated every reliable cam frame
last_body_cx     = NaN;
last_body_cy     = NaN;
last_body_hax_x  = NaN;   % head-axis unit vector in tactile space
last_body_hax_y  = NaN;
last_body_rax_x  = NaN;   % right-axis unit vector in tactile space
last_body_rax_y  = NaN;
last_body_hlen   = NaN;   % half body length
last_body_offset = NaN;   % smooth_offset (FB split)
last_body_reliable = false;

ci1       = 2;
last_wall = 0;
progress_last_print = -Inf;
progress_print_interval_sec = 5;
progress_bar_width = 24;

% CLUSTER STRUCT ARRAY
% Fields:
%   cx, cy           — current centroid (tactile px)
%   cx_sum, cy_sum   — running sum for mean
%   n_obs            — frames matched
%   last_frame       — frame_idx of last matched blob
%   open             — true until liftoff
%   label            — [] pending during tracking | 0=noise | 1=FL 2=FR 3=HL 4=HR
%   label_source     — string describing how label was assigned
%   ic_label_done    — true once IC lock has fired
%   close_frame      — frame_idx at liftoff
%   close_time       — timestamp (s) at liftoff, for swing-phase gate
%   valid_stance     — true only if stance duration passes minimum duration
%   dynamics         — per-frame spatial and pressure summaries
%   display_cx/cy    — mean centroid for label placement
clusters = struct('cx',{},'cy',{},'cx_sum',{},'cy_sum',{},'n_obs',{}, ...
                  'start_frame',{},'start_time',{},'last_frame',{}, ...
                  'last_time',{},'start_cx',{},'start_cy',{}, ...
                  'open',{},'label',{},'label_source',{}, ...
                  'ic_label_done',{},'quad_votes',{},'close_frame',{},'close_time',{}, ...
                  'valid_stance',{},'dynamics',{},'display_cx',{},'display_cy',{});
% Rejected tactile components are tracked separately so they are exported
% as noise without entering the expensive paw-labeling state machine.
noise_clusters = clusters;

frame_idx = 0;

% Per-frame body-axis log: the body axis (tail to body centroid, from the
% overhead-camera body mask and the tail-base estimate) computed below for
% the fore/hind quadrant split. It is saved with the detector output
% (body_axis_trace) so that later stages can use the same body-orientation
% signal. Frames without a reliable body estimate are left NaN; a consumer
% should hold the last valid value, as this detector does with
% last_body_cx and related variables.
body_axis_log_t       = nan(n_frames, 1);
body_axis_log_cx      = nan(n_frames, 1);
body_axis_log_cy      = nan(n_frames, 1);
body_axis_log_hax_x   = nan(n_frames, 1);
body_axis_log_hax_y   = nan(n_frames, 1);
body_axis_log_rax_x   = nan(n_frames, 1);
body_axis_log_rax_y   = nan(n_frames, 1);
body_axis_log_offset  = nan(n_frames, 1);
body_axis_log_reliable = false(n_frames, 1);

if EXPORT_FOOTSTEP_DYNAMICS
    pressure_frames = zeros(P_H, P_W, n_frames, 'uint16');
    pressure_times = nan(n_frames, 1);
    pressure_frame_indices = nan(n_frames, 1);
end

% CoP velocity state
cop_hist     = nan(COP_VEL_WINDOW, 2);  % rolling buffer of [cop_x, cop_y]
cop_hist_t   = nan(COP_VEL_WINDOW, 1);  % timestamps for each entry
cop_buf_idx  = 0;   % how many entries filled (capped at COP_VEL_WINDOW)
cop_speed    = 0;   % current smoothed CoP speed (tactile px/s)
rat_is_moving = false;

tic;
progress_tic = tic;
fprintf('Main processing: %d synchronized frames to process.\n', n_frames);

% =======================================================================
% MAIN LOOP
% =======================================================================
for time_idx = 1:n_frames
    if ~ishandle(f)||~isvalid(f), break; end
    t = all_times(time_idx);
    frame_idx = frame_idx + 1;

    % ---- Pause / speed ------------------------------------------------
    if SHOW_SEGMENTATION_FIGURE
        while true
            cs = get(ctrl_panel,'UserData');
            if ~cs.is_paused, break; end
            pause(0.05); drawnow;
            if ~ishandle(f)||~isvalid(f), break; end
        end
        if ~ishandle(f)||~isvalid(f), break; end
        cs = get(ctrl_panel,'UserData');
        playback_speed = cs.playback_speed;
    end

    % ---- Tactile -------------------------------------------------------
    tac_updated = false;
    for i = 1:numel(board_names)
        bn = board_names{i};
        board_id = [];
        if isfield(data,[bn '_board_ids'])
            v = data.([bn '_board_ids']);
            if isnumeric(v), board_id=v(1); elseif iscell(v), board_id=v{1}; end
        end
        if isempty(board_id)
            tmp = sscanf(bn,'Board%d'); if ~isempty(tmp), board_id=tmp; end
        end
        if isempty(board_id)||board_id<1||board_id>max_board_id, continue; end

        bts = board_ts_norm.(bn); nb = length(bts);
        bi  = tidx_by_board(board_id); adv = false;
        while bi<nb && bts(bi+1)<=t, bi=bi+1; adv=true; end
        tidx_by_board(board_id) = bi;
        if bts(bi)>t, continue; end
        if ~adv && bi>1, continue; end

        ir = data.([bn '_pixel_indices']); vr = data.([bn '_pixel_values']);
        if iscell(ir), inds=ir{bi}; vals=vr{bi};
        elseif isnumeric(ir)
            inds=ir(bi,:); vals=vr(bi,:);
            ok=inds~=0; inds=inds(ok); vals=vals(ok);
        else, continue; end

        img = zeros(board_size);
        if ~isempty(inds)
            if USE_VECTOR_PRESSURE_ASSEMBLY
                [r,c] = index_to_coords(inds(:));
                vals = vals(:);
                ok = r>=1 & r<=board_size & c>=1 & c<=board_size;
                img(sub2ind([board_size board_size], r(ok), c(ok))) = vals(ok);
            else
                for pi = 1:numel(inds)
                    idx = double(inds(pi));
                    if idx <= 0
                        continue;
                    end
                    [r,c] = index_to_coords(idx);
                    if r>=1 && r<=board_size && c>=1 && c<=board_size
                        img(r,c) = vals(pi);
                    end
                end
            end
        end
        board_imgs_by_id{board_id} = apply_transform(img,transforms_by_id{board_id});
        tac_updated = true;
    end

    if tac_updated
        combined = zeros(board_size*grid_rows, board_size*grid_cols);
        for pos = 1:numel(layout_board_ids)
            bid = layout_board_ids(pos);
            if bid<1||bid>max_board_id, continue; end
            gr = floor((pos-1)/grid_cols); gc = mod(pos-1,grid_cols);
            rs = gr*board_size+1; cs_i = gc*board_size+1;
            combined(rs:rs+63,cs_i:cs_i+63) = board_imgs_by_id{bid};
        end
        if UPDATE_SEGMENTATION_DISPLAY
            set(h_tac,'CData',combined);
        end
    end

    if EXPORT_FOOTSTEP_DYNAMICS
        pressure_frames(:,:,frame_idx) = uint16(max(0, min(combined, double(intmax('uint16')))));
        pressure_times(frame_idx) = t;
        pressure_frame_indices(frame_idx) = frame_idx;
    end

    % ---- Camera + body geometry ----------------------------------------
    c1_updated   = false;
    is_standing  = false;
    near_edge    = false;
    anchor_fired = false;
    body_reliable_this_frame = false;

    while ci1<=n_cam1 && tscam1_n(ci1)<=t
        if ci1==n_cam1 || tscam1_n(ci1+1)>t
            if hasFrame(cam1)
                current_cam1_idx = ci1;
                raw_frame1 = readFrame(cam1);
                if UPDATE_SEGMENTATION_DISPLAY
                    set(h_c1,'CData',rot90(raw_frame1,2));
                end
                c1_updated = true;
            end
        end
        ci1 = ci1+1;
    end

    if c1_updated && ~isempty(raw_frame1)
        diff_img = abs(double(rgb2gray(rot90(raw_frame1,2))) - double(bg_gray));
        mask = diff_img > bg_diff_thresh;
        mask = imclose(mask,strel('disk',4));
        mask = imopen(mask, strel('disk',3));
        mask = imfill(mask,'holes');

        cc    = bwconncomp(mask);
        props = regionprops(cc,'Area','PixelIdxList');
        mask(:) = false;
        for kb = 1:numel(props)
            if props(kb).Area >= min_blob_area
                mask(props(kb).PixelIdxList) = true;
            end
        end

        current_area = sum(mask(:));
        % A shrunken body-mask area alone is not sufficient evidence of
        % rearing/standing on the runway (head-down sniffing, partial wall
        % occlusion, and normal stride phases can all shrink the visible
        % top-down silhouette without the rat rearing). Standing/rearing
        % has a second, independent signature: only the hindpaws remain in
        % contact (at most two open contacts). Both conditions are required
        % before the frame is flagged as standing.
        n_open_clusters_for_standing = sum([clusters.open]);
        is_standing  = (current_area > 0) && (current_area < standing_threshold) && ...
            (n_open_clusters_for_standing <= 2);

        cc2 = bwconncomp(mask);
        if cc2.NumObjects > 0
            sizes  = cellfun(@numel,cc2.PixelIdxList);
            [~,li] = max(sizes);
            mask(:) = false;
            mask(cc2.PixelIdxList{li}) = true;

            ref_out  = imref2d([P_H,P_W]);
            rat_mask = imwarp(uint8(mask)*255,tform,'OutputView',ref_out) > 128;

            cc_w = bwconncomp(rat_mask);
            if cc_w.NumObjects > 1
                sizes_w  = cellfun(@numel,cc_w.PixelIdxList);
                [~,li_w] = max(sizes_w);
                rat_mask(:) = false;
                rat_mask(cc_w.PixelIdxList{li_w}) = true;
            end
            body_clipped = any(rat_mask(1:body_clip_margin_px,:), 'all') || ...
                any(rat_mask(end-body_clip_margin_px+1:end,:), 'all') || ...
                any(rat_mask(:,1:body_clip_margin_px), 'all') || ...
                any(rat_mask(:,end-body_clip_margin_px+1:end), 'all');
            body_edge_px = nnz(rat_mask(1,:)) + nnz(rat_mask(end,:)) + ...
                nnz(rat_mask(:,1)) + nnz(rat_mask(:,end));
            body_edge_frac = body_edge_px / max(1, nnz(rat_mask));

            rp = regionprops(rat_mask,'Centroid','Orientation','MajorAxisLength');
            if ~isempty(rp)
                cx       = rp(1).Centroid(1);
                cy       = rp(1).Centroid(2);
                half_len = rp(1).MajorAxisLength/2;
                near_edge = cx<edge_margin_px || cx>P_W-edge_margin_px || ...
                            cy<edge_margin_px || cy>P_H-edge_margin_px;
                body_reliable_this_frame = ~near_edge && ...
                    body_edge_frac <= body_edge_contact_frac_max;

                B = bwboundaries(rat_mask,'noholes');
                if ~isempty(B)
                    [~,bi_] = max(cellfun(@(b)size(b,1),B));
                    last_outline_x = B{bi_}(:,2);
                    last_outline_y = B{bi_}(:,1);
                end
                last_cx = cx; last_cy = cy;

                if body_reliable_this_frame
                    cam_frame_count = cam_frame_count + 1;

                    ang = deg2rad(rp(1).Orientation);
                    dx  = cos(ang); dy = -sin(ang);
                    raw_ax_x = dx; raw_ax_y = dy;

                    got_model_tail = false;
                    [model_tail_x, model_tail_y, model_tail_conf] = ...
                        tailbase_prediction_for_frame(tailbase_predictions, ...
                        current_cam1_idx);
                    % Tail-base predictions with confidence below
                    % tailbase_confidence_min are ignored. Before the rat
                    % enters the platform (empty warped mask), the network
                    % returns low confidence (about 0.04-0.06) with the
                    % prediction at a corner pixel.
                    tailbase_confidence_min = 0.5;
                    model_tail_ok = isfinite(model_tail_x) && ...
                        isfinite(model_tail_y) && ...
                        (isnan(model_tail_conf) || ...
                        model_tail_conf >= tailbase_confidence_min);
                    if model_tail_ok
                        tail_dist = hypot(cx - model_tail_x, cy - model_tail_y);
                        if tail_dist >= tail_centroid_min_dist_px
                            raw_ax_x = (cx - model_tail_x) / tail_dist;
                            raw_ax_y = (cy - model_tail_y) / tail_dist;
                            tail_mid_x = model_tail_x;
                            tail_mid_y = model_tail_y;
                            last_tail_x = model_tail_x;
                            last_tail_y = model_tail_y;
                            got_model_tail = true;
                        end
                    end

                    if exist('bwskel','builtin')||exist('bwskel','file')
                        skel = bwskel(rat_mask);
                    else
                        skel = bwmorph(rat_mask,'skel',Inf);
                    end
                    nb_cnt = conv2(double(skel),ones(3),'same');
                    ep_map = skel & (nb_cnt==2);
                    [ey,ex] = find(ep_map);

                    got_skel = false;
                    if ~got_model_tail && ~isempty(ex)
                        dists     = sqrt((ex-cx).^2+(ey-cy).^2);
                        [~,tip_i] = max(dists);
                        tail_mid_x = ex(tip_i); tail_mid_y = ey(tip_i);

                        walk_x = tail_mid_x; walk_y = tail_mid_y;
                        visited = false(size(skel));
                        visited(tail_mid_y,tail_mid_x) = true;
                        path_x = tail_mid_x; path_y = tail_mid_y;
                        [nrows,ncols] = size(skel);
                        while true
                            ny = walk_y+[-1 -1 -1  0  0  1  1  1];
                            nx = walk_x+[-1  0  1 -1  1 -1  0  1];
                            v2 = ny>=1&ny<=nrows&nx>=1&nx<=ncols;
                            ny=ny(v2); nx=nx(v2);
                            is_sk=false(1,numel(nx));
                            for ni=1:numel(nx)
                                is_sk(ni)=skel(ny(ni),nx(ni))&&~visited(ny(ni),nx(ni));
                            end
                            ny=ny(is_sk); nx=nx(is_sk);
                            if isempty(nx), break; end
                            nd=sqrt((nx-cx).^2+(ny-cy).^2);
                            [~,best]=min(nd);
                            walk_x=nx(best); walk_y=ny(best);
                            visited(walk_y,walk_x)=true;
                            path_x(end+1)=walk_x; path_y(end+1)=walk_y; %#ok<AGROW>
                        end
                        mid_i      = max(1,round(numel(path_x)*0.5));
                        tail_mid_x = path_x(mid_i);
                        tail_mid_y = path_y(mid_i);

                        tail_dist = sqrt((cx-tail_mid_x)^2 + ...
                            (cy-tail_mid_y)^2);
                        if tail_dist >= tail_centroid_min_dist_px
                            raw_ax_x = (cx-tail_mid_x) / tail_dist;
                            raw_ax_y = (cy-tail_mid_y) / tail_dist;
                        else
                            tax = cx-tail_mid_x; tay = cy-tail_mid_y;
                            tlen = sqrt(tax^2+tay^2)+1e-6;
                            tax = tax/tlen; tay = tay/tlen;
                            if (raw_ax_x*tax + raw_ax_y*tay) < 0
                                raw_ax_x = -raw_ax_x;
                                raw_ax_y = -raw_ax_y;
                            end
                        end

                        last_tail_x = tail_mid_x;
                        last_tail_y = tail_mid_y;
                        got_skel = true;
                    end
                    if got_model_tail
                        got_skel = true;
                    end

                    [head_ax_x, head_ax_y, previous_axis_x, previous_axis_y, ...
                        pending_flip_x, pending_flip_y, pending_flip_count, ...
                        last_axis_frame, anchor_fired] = ...
                        keep_axis_sign_with_hysteresis(raw_ax_x, raw_ax_y, ...
                        previous_axis_x, previous_axis_y, pending_flip_x, ...
                        pending_flip_y, pending_flip_count, last_axis_frame, ...
                        frame_idx, axis_flip_confirm_frames);

                    [rows_m,cols_m] = find(rat_mask);
                    fb_proj  = (cols_m-cx)*head_ax_x + (rows_m-cy)*head_ax_y;
                    total_px = numel(rows_m);
                    target   = fb_split_target * total_px;
                    lo = -half_len; hi = half_len;
                    for iter=1:20
                        ms=(lo+hi)/2;
                        if sum(fb_proj>=ms)>target, lo=ms; else, hi=ms; end
                    end
                    raw_offset = (lo+hi)/2;
                    if isnan(smooth_offset)
                        smooth_offset = raw_offset;
                    else
                        smooth_offset = offset_smooth_alpha*smooth_offset + ...
                                        (1-offset_smooth_alpha)*raw_offset;
                    end

                    r_ax_x = -head_ax_y;
                    r_ax_y =  head_ax_x;
                    fb_rel  = fb_proj - smooth_offset;
                    lr_proj = (cols_m-cx)*r_ax_x + (rows_m-cy)*r_ax_y;

                    idx_FL = fb_rel>=0 & lr_proj< 0;
                    idx_FR = fb_rel>=0 & lr_proj>=0;
                    idx_HL = fb_rel< 0 & lr_proj< 0;
                    idx_HR = fb_rel< 0 & lr_proj>=0;
                    quad_idx_cells = {idx_FL, idx_FR, idx_HL, idx_HR};

                    last_quad_assigned = true;
                    for qi=1:4
                        qm = false(size(rat_mask));
                        if any(quad_idx_cells{qi})
                            qm(sub2ind(size(rat_mask), ...
                                rows_m(quad_idx_cells{qi}), ...
                                cols_m(quad_idx_cells{qi}))) = true;
                        end
                        last_quad_masks{qi} = qm;
                        Bq = bwboundaries(qm,'noholes');
                        if ~isempty(Bq)
                            [~,biq] = max(cellfun(@(b)size(b,1),Bq));
                            last_quad_bx{qi} = Bq{biq}(:,2);
                            last_quad_by{qi} = Bq{biq}(:,1);
                        end
                    end

                    % Snapshot for heuristics
                    last_body_cx     = cx;
                    last_body_cy     = cy;
                    last_body_hax_x  = head_ax_x;
                    last_body_hax_y  = head_ax_y;
                    last_body_rax_x  = r_ax_x;
                    last_body_rax_y  = r_ax_y;
                    last_body_hlen   = half_len;
                    last_body_offset = smooth_offset;
                    last_body_reliable = body_reliable_this_frame;

                    body_axis_log_t(time_idx)        = t;
                    body_axis_log_cx(time_idx)       = cx;
                    body_axis_log_cy(time_idx)       = cy;
                    body_axis_log_hax_x(time_idx)    = head_ax_x;
                    body_axis_log_hax_y(time_idx)    = head_ax_y;
                    body_axis_log_rax_x(time_idx)    = r_ax_x;
                    body_axis_log_rax_y(time_idx)    = r_ax_y;
                    body_axis_log_offset(time_idx)   = smooth_offset;
                    body_axis_log_reliable(time_idx) = body_reliable_this_frame;

                    last_axis_x = [cx-head_ax_x*half_len, cx+head_ax_x*half_len];
                    last_axis_y = [cy-head_ax_y*half_len, cy+head_ax_y*half_len];
                    if got_skel
                        last_arrow_ox = tail_mid_x; last_arrow_oy = tail_mid_y;
                        last_arrow_ux = cx-tail_mid_x; last_arrow_uy = cy-tail_mid_y;
                    else
                        al = half_len*0.5;
                        last_arrow_ox = cx-head_ax_x*al; last_arrow_oy = cy-head_ax_y*al;
                        last_arrow_ux = head_ax_x*al*2;  last_arrow_uy = head_ax_y*al*2;
                    end

                end  % body_reliable_this_frame
                if ~body_reliable_this_frame
                    last_quad_assigned = false;
                    last_body_reliable = false;
                    last_quad_masks    = {[],[],[],[]};
                    last_quad_bx       = {NaN,NaN,NaN,NaN};
                    last_quad_by       = {NaN,NaN,NaN,NaN};
                end
            end  % rp non-empty
        end  % rat found
    end  % c1_updated

    % BLOB DETECTION
    press_mask = combined > PRESSURE_THRESH;
    press_mask = imopen(press_mask, strel('disk',1));
    press_mask = imfill(press_mask,'holes');

    cc_fp    = bwconncomp(press_mask);
    fp_props = regionprops(cc_fp,'Area','Centroid','PixelIdxList');
    fp_props = annotate_source_component_count(fp_props, 1);
    fp_props_before_merge = fp_props;
    fp_props = merge_nearby_footprint_props(fp_props, combined, ...
        PRELABEL_MERGE_DIST_PX, PRELABEL_MERGE_EDGE_GAP_PX, ...
        PRELABEL_MERGE_DILATE_RADIUS_PX, PRELABEL_MERGE_MAX_AREA, ...
        PRELABEL_MERGE_SEAM_MAX_AREA, board_size);
    if PRELABEL_MERGE_DEBUG && frame_idx >= PRELABEL_MERGE_DEBUG_FRAME_START && ...
            frame_idx <= PRELABEL_MERGE_DEBUG_FRAME_END
        print_prelabel_merge_debug(frame_idx, fp_props_before_merge, fp_props, ...
            combined, PRELABEL_MERGE_DIST_PX, PRELABEL_MERGE_EDGE_GAP_PX, ...
            PRELABEL_MERGE_DILATE_RADIUS_PX, PRELABEL_MERGE_MAX_AREA, ...
            PRELABEL_MERGE_SEAM_MAX_AREA, board_size);
    end
    fp_props = split_multipeak_footprint_props(fp_props, combined, ...
        PRELABEL_SPLIT_MULTIPEAK, MIN_CONTACT_AREA, PRELABEL_SPLIT_MIN_AREA, ...
        PRELABEL_SPLIT_MIN_PEAK_DIST_PX, PRELABEL_SPLIT_MIN_PROMINENCE);
    if PRELABEL_MERGE_DEBUG && frame_idx >= PRELABEL_MERGE_DEBUG_FRAME_START && ...
            frame_idx <= PRELABEL_MERGE_DEBUG_FRAME_END
        fprintf('prelabel f%d after split: props=%d counts=[%s]\n', ...
            frame_idx, numel(fp_props), format_numeric_row([fp_props.SourceComponentCount]));
    end

    valid_fp = [];
    rejected_fp = [];
    % Components inside a reliable projected body quadrant are contact
    % evidence.  Keep their quadrant label so the size/peak gate cannot
    % misclassify a fragmented footprint as noise.
    body_mask_label = zeros(1, numel(fp_props));
    reject_debug = struct('x',{},'y',{},'reason',{});
    for ki = 1:numel(fp_props)
        [is_peak_candidate, peak_reason] = is_peak_seed_candidate( ...
            fp_props(ki), combined, PEAK_SEED_MIN_DENSITY, ...
            PEAK_SEED_MIN_MEAN_PRESSURE, PEAK_SEED_CANDIDATE_MODE);
        is_tail_candidate = REJECT_TAILBASE_CONTACTS && ...
            is_tailbase_candidate(fp_props(ki).Centroid, ...
                last_tail_x, last_tail_y, last_body_cx, last_body_cy, ...
                last_body_hax_x, last_body_hax_y, last_body_hlen, ...
                TAILBASE_REJECT_RADIUS_PX, TAILBASE_REJECT_BEHIND_FRAC, ...
                TAILBASE_REJECT_MIDLINE_PX);
        [in_body_mask, quad_label] = component_body_mask_label( ...
            fp_props(ki), last_quad_masks, last_quad_assigned, ...
            last_body_reliable);
        body_mask_label(ki) = quad_label;
        if ((fp_props(ki).Area >= MIN_CONTACT_AREA && is_peak_candidate) || ...
                in_body_mask) && ...
                ~is_tail_candidate
            valid_fp(end+1) = ki; %#ok<AGROW>
        else
            rejected_fp(end+1) = ki; %#ok<AGROW>
            if DEBUG_FOOTPRINT_CANDIDATES
                reason = candidate_reject_reason(fp_props(ki), MIN_CONTACT_AREA, ...
                    peak_reason, is_tail_candidate);
                reject_debug(end+1).x = fp_props(ki).Centroid(1); %#ok<AGROW>
                reject_debug(end).y = fp_props(ki).Centroid(2);
                reject_debug(end).reason = reason;
            end
        end
    end

    % CENTER-OF-PRESSURE VELOCITY  (locomotion detector)
    % Compute the pressure-weighted centroid of the full tactile map,
    % store it in a circular buffer, then estimate speed as the total
    % displacement over the buffer window divided by its time span.
    total_pressure = sum(combined(:));
    if total_pressure > 0
        [row_idx, col_idx] = ndgrid(1:size(combined,1), 1:size(combined,2));
        cop_x = sum(sum(combined .* col_idx)) / total_pressure;
        cop_y = sum(sum(combined .* row_idx)) / total_pressure;
    else
        cop_x = NaN; cop_y = NaN;
    end

    if ~isnan(cop_x)
        cop_buf_idx = cop_buf_idx + 1;
        buf_pos = mod(cop_buf_idx - 1, COP_VEL_WINDOW) + 1;
        cop_hist(buf_pos, :) = [cop_x, cop_y];
        cop_hist_t(buf_pos)  = t;

        if cop_buf_idx >= 2
            % Oldest entry in the circular buffer
            n_filled   = min(cop_buf_idx, COP_VEL_WINDOW);
            oldest_pos = mod(cop_buf_idx - n_filled, COP_VEL_WINDOW) + 1;
            ox = cop_hist(oldest_pos, 1); oy = cop_hist(oldest_pos, 2);
            ot = cop_hist_t(oldest_pos);
            dt_cop = t - ot;
            if dt_cop > 0 && ~isnan(ox)
                displacement = sqrt((cop_x-ox)^2 + (cop_y-oy)^2);
                cop_speed    = displacement / dt_cop;  % tactile px/s
            end
        end
    end
    rat_is_moving = (cop_speed >= COP_MOVING_THRESH_PX_S);

    % MATCH blobs to open clusters
    n_clusters   = numel(clusters);
    blob_matched = false(1, numel(valid_fp));

    for ki = 1:numel(valid_fp)
        prop_idx = valid_fp(ki);
        bcx = fp_props(prop_idx).Centroid(1);
        bcy = fp_props(prop_idx).Centroid(2);
        blob_dyn = make_blob_dynamics(frame_idx, t, fp_props(prop_idx), combined);
        best_c = 0; best_d = CLUSTER_DIST_PX + 1;
        for ci2 = 1:n_clusters
            if ~clusters(ci2).open, continue; end
            if (frame_idx - clusters(ci2).last_frame) > CLUSTER_GAP_FRAMES, continue; end
            d = sqrt((clusters(ci2).cx-bcx)^2 + (clusters(ci2).cy-bcy)^2);
            drift = sqrt((clusters(ci2).start_cx-bcx)^2 + ...
                (clusters(ci2).start_cy-bcy)^2);
            if drift > CLUSTER_MAX_DRIFT_PX, continue; end
            if is_proximal_new_contact(clusters(ci2), bcx, bcy, ...
                    last_body_cx, last_body_cy, last_body_hax_x, ...
                    last_body_hax_y, last_body_reliable, ...
                    PROXIMAL_NEW_CONTACT_PX)
                continue;
            end
            if d < best_d, best_d = d; best_c = ci2; end
        end
        if best_c > 0
            clusters(best_c).cx         = bcx;
            clusters(best_c).cy         = bcy;
            clusters(best_c).cx_sum     = clusters(best_c).cx_sum + bcx;
            clusters(best_c).cy_sum     = clusters(best_c).cy_sum + bcy;
            clusters(best_c).n_obs      = clusters(best_c).n_obs  + 1;
            clusters(best_c).last_frame = frame_idx;
            clusters(best_c).last_time  = t;
            clusters(best_c).dynamics   = append_dynamics(clusters(best_c).dynamics, blob_dyn);
            % Fill only an unresolved track: a reliable mask observation
            % is direct paw evidence, but must not repaint a paw already
            % tracked through a crossing.
            if body_mask_label(prop_idx) > 0 && ...
                    (isempty(clusters(best_c).label) || clusters(best_c).label == 0)
                clusters(best_c).label         = body_mask_label(prop_idx);
                clusters(best_c).label_source  = 'body_mask_footprint';
                clusters(best_c).ic_label_done = true;
            end
            blob_matched(ki) = true;
        end
    end

    % OPEN new clusters for unmatched blobs
    for ki = 1:numel(valid_fp)
        if blob_matched(ki), continue; end
        prop_idx = valid_fp(ki);
        bcx = fp_props(prop_idx).Centroid(1);
        bcy = fp_props(prop_idx).Centroid(2);
        blob_dyn = make_blob_dynamics(frame_idx, t, fp_props(prop_idx), combined);
        % Append directly into the struct array — avoids the dot-indexing
        % error that occurs when assigning to a plain scalar struct and
        % then trying to concatenate it with a typed empty struct array.
        ni = numel(clusters) + 1;
        clusters(ni).cx            = bcx;
        clusters(ni).cy            = bcy;
        clusters(ni).cx_sum        = bcx;
        clusters(ni).cy_sum        = bcy;
        clusters(ni).n_obs         = 1;
        clusters(ni).start_frame   = frame_idx;
        clusters(ni).start_time    = t;
        clusters(ni).last_frame    = frame_idx;
        clusters(ni).last_time     = t;
        clusters(ni).start_cx      = bcx;
        clusters(ni).start_cy      = bcy;
        clusters(ni).open          = true;
        if body_mask_label(prop_idx) > 0
            clusters(ni).label         = body_mask_label(prop_idx);
            clusters(ni).label_source  = 'body_mask_footprint';
            clusters(ni).ic_label_done = true;
        else
            clusters(ni).label         = [];
            clusters(ni).label_source  = '';
            clusters(ni).ic_label_done = false;
        end
        clusters(ni).quad_votes    = zeros(1,4);
        clusters(ni).close_frame   = [];
        clusters(ni).close_time    = [];
        clusters(ni).valid_stance  = false;
        clusters(ni).dynamics      = append_dynamics(empty_dynamics(), blob_dyn);
        clusters(ni).display_cx    = bcx;
        clusters(ni).display_cy    = bcy;
    end

    noise_clusters = update_rejected_noise_clusters(noise_clusters, ...
        fp_props(rejected_fp), frame_idx, t, combined, CLUSTER_DIST_PX, ...
        CLUSTER_MAX_DRIFT_PX, CLUSTER_GAP_FRAMES);

    clusters = merge_duplicate_open_clusters(clusters, OPEN_CLUSTER_MERGE_DIST_PX, ...
        last_body_cx, last_body_cy, last_body_hax_x, last_body_hax_y, ...
        last_body_reliable, PROXIMAL_NEW_CONTACT_PX);

    % Safety net: after duplicate merging, every accepted pressure
    % component in this frame must still have a live cluster. This prevents
    % a real simultaneous footprint from vanishing when earlier linking or
    % duplicate resolution makes a bad decision.
    for ki = 1:numel(valid_fp)
        bcx = fp_props(valid_fp(ki)).Centroid(1);
        bcy = fp_props(valid_fp(ki)).Centroid(2);
        has_current_cluster = false;
        for ci2 = 1:numel(clusters)
            if ~clusters(ci2).open || clusters(ci2).last_frame ~= frame_idx
                continue;
            end
            if hypot(clusters(ci2).cx - bcx, clusters(ci2).cy - bcy) <= ...
                    CLUSTER_DIST_PX
                has_current_cluster = true;
                break;
            end
        end
        if ~has_current_cluster
            blob_dyn = make_blob_dynamics(frame_idx, t, ...
                fp_props(valid_fp(ki)), combined);
            ni = numel(clusters) + 1;
            clusters(ni).cx            = bcx;
            clusters(ni).cy            = bcy;
            clusters(ni).cx_sum        = bcx;
            clusters(ni).cy_sum        = bcy;
            clusters(ni).n_obs         = 1;
            clusters(ni).start_frame   = frame_idx;
            clusters(ni).start_time    = t;
            clusters(ni).last_frame    = frame_idx;
            clusters(ni).last_time     = t;
            clusters(ni).start_cx      = bcx;
            clusters(ni).start_cy      = bcy;
            clusters(ni).open          = true;
            prop_idx = valid_fp(ki);
            if body_mask_label(prop_idx) > 0
                clusters(ni).label         = body_mask_label(prop_idx);
                clusters(ni).label_source  = 'body_mask_footprint+safety_orphan_reopened';
                clusters(ni).ic_label_done = true;
            else
                clusters(ni).label         = [];
                clusters(ni).label_source  = 'safety_orphan_reopened';
                clusters(ni).ic_label_done = false;
            end
            clusters(ni).quad_votes    = zeros(1,4);
            clusters(ni).close_frame   = [];
            clusters(ni).close_time    = [];
            clusters(ni).valid_stance  = false;
            clusters(ni).dynamics      = append_dynamics(empty_dynamics(), blob_dyn);
            clusters(ni).display_cx    = bcx;
            clusters(ni).display_cy    = bcy;
        end
    end

    % IC lock with spatial consistency check
    % ===================================================================
    % For every open cluster that does not yet have a locked label,
    % attempt to assign one using the current body-mask overlap.
    % The label is locked permanently once assigned — it will NOT change
    % in subsequent frames even if the body axis drifts or flips.
    if last_quad_assigned && last_body_reliable
        for ci2 = 1:numel(clusters)
            if ~clusters(ci2).open || is_explicit_noise_cluster(clusters(ci2))
                continue;
            end

            % Find the blob pixel list for this cluster
            pix = [];
            for ki = 1:numel(valid_fp)
                bcx = fp_props(valid_fp(ki)).Centroid(1);
                bcy = fp_props(valid_fp(ki)).Centroid(2);
                if sqrt((clusters(ci2).cx-bcx)^2+(clusters(ci2).cy-bcy)^2) < CLUSTER_DIST_PX
                    pix = fp_props(valid_fp(ki)).PixelIdxList;
                    break;
                end
            end
            if isempty(pix), continue; end

            pos_lbl_fallback = position_label_from_body_axis(clusters(ci2).cx, ...
                clusters(ci2).cy, last_body_cx, last_body_cy, ...
                last_body_hax_x, last_body_hax_y, last_body_rax_x, ...
                last_body_rax_y, last_body_offset);

            % Count body-mask overlap per quadrant
            votes = zeros(1,4);
            for qi = 1:4
                if ~isempty(last_quad_masks{qi})
                    votes(qi) = sum(last_quad_masks{qi}(pix));
                end
            end

            if sum(votes) < IC_MIN_OVERLAP_PX && pos_lbl_fallback > 0
                votes(:) = 0;
                votes(pos_lbl_fallback) = IC_MIN_OVERLAP_PX;
                alt_lbl = opposite_same_girdle_label(pos_lbl_fallback);
                if alt_lbl > 0
                    votes(alt_lbl) = IC_MIN_OVERLAP_PX - 1;
                end
            end

            if sum(votes) < IC_MIN_OVERLAP_PX
                continue;  % insufficient evidence — retry next frame
            end

            clusters(ci2).quad_votes = clusters(ci2).quad_votes + votes;

            if clusters(ci2).ic_label_done, continue; end

            % Sort votes descending so we can walk down to find the
            % best label that also passes the spatial check.
            [sorted_votes, sort_order] = sort(votes, 'descend');

            % Build forbidden-label set from the same-paw minimum swing
            % gate. This is enforced regardless of locomotion state because
            % a near-instant re-contact of the same paw is not biological.
            forbidden = false(1,4);
            for fci = 1:numel(clusters)
                if clusters(fci).open, continue; end
                if ~cluster_is_valid_stance(clusters(fci), GAIT_MIN_STANCE_SEC)
                    continue;
                end
                flbl = clusters(fci).label;
                if isempty(flbl) || flbl == 0, continue; end
                if ~isempty(clusters(fci).close_time)
                    if (t - clusters(fci).close_time) < SWING_MIN_SEC
                        forbidden(flbl) = true;
                    end
                end
            end

            % Walk vote ranking to find the best spatially-consistent,
            % swing-legal label.
            chosen_lbl = 0;
            src = '';
            for rank = 1:4
                if sorted_votes(rank) == 0, break; end
                cand = sort_order(rank);

                % Spatial consistency check
                if last_body_reliable && ~isnan(last_body_cx)
                    bcx_c = clusters(ci2).cx;
                    bcy_c = clusters(ci2).cy;
                    fb_blob = (bcx_c - last_body_cx)*last_body_hax_x + ...
                              (bcy_c - last_body_cy)*last_body_hax_y ...
                              - last_body_offset;
                    lr_blob = (bcx_c - last_body_cx)*last_body_rax_x + ...
                              (bcy_c - last_body_cy)*last_body_rax_y;
                    pos_is_front  = (fb_blob >= 0);
                    pos_is_left   = (lr_blob <  0);
                    pos_lbl = 1 + 2*double(~pos_is_front) + double(~pos_is_left);
                    vote_is_front = (cand == 1 || cand == 2);
                    if pos_is_front ~= vote_is_front
                        % FB mismatch: use positional label instead
                        cand = pos_lbl;
                        src  = 'IC+spatial_override';
                    else
                        if isempty(src), src = 'IC'; end
                    end
                else
                    if isempty(src), src = 'IC'; end
                end

                % Swing-phase gate
                if forbidden(cand)
                    src = '';   % reset so next iteration can set it
                    continue;  % try next-best vote
                end
                if label_is_open_elsewhere(clusters, ci2, cand, t, GAIT_MIN_STANCE_SEC)
                    src = '';   % same paw is already in stance
                    continue;  % try next-best vote
                end
                if last_body_reliable && ~same_girdle_pair_is_plausible( ...
                        clusters, ci2, cand, last_body_cx, last_body_cy, ...
                        last_body_hax_x, last_body_hax_y, ...
                        SAME_GIRDLE_PAIR_MAX_FB_SEP_PX)
                    src = '';   % FL/FR or HL/HR too far apart along FB axis
                    continue;  % try next-best vote
                end

                chosen_lbl = cand;
                break;
            end

            if chosen_lbl == 0
                % All candidate labels are swing-forbidden — stay pending
                continue;
            end

            clusters(ci2).label         = chosen_lbl;
            clusters(ci2).label_source  = src;
            clusters(ci2).ic_label_done = true;
        end
    end

    open_ci = find(arrayfun(@(c) c.open && ~is_explicit_noise_cluster(c), clusters));
    hind_heuristic_fired = false;

    if numel(open_ci) == 2 && last_body_reliable && ...
            ~isnan(last_body_cx) && ~isnan(last_body_hax_x)
        ci_a = open_ci(1);
        ci_b = open_ci(2);

        % RAW front/back projection — no smooth_offset subtraction.
        % Positive = in front of body centroid, negative = behind it.
        fb_a_raw = (clusters(ci_a).cx - last_body_cx)*last_body_hax_x + ...
                   (clusters(ci_a).cy - last_body_cy)*last_body_hax_y;
        fb_b_raw = (clusters(ci_b).cx - last_body_cx)*last_body_hax_x + ...
                   (clusters(ci_b).cy - last_body_cy)*last_body_hax_y;

        hind_thresh = -HIND_FB_THRESH * last_body_hlen;  % <= 0

        % Left/right edge condition (tactile-space body centroid)
        body_on_lr_edge = (last_body_cx <= HIND_EDGE_MARGIN_PX) || ...
                          (last_body_cx >= P_W - HIND_EDGE_MARGIN_PX);
        contacts_on_lr_edge = ...
            (clusters(ci_a).cx <= HIND_EDGE_MARGIN_PX && ...
             clusters(ci_b).cx <= HIND_EDGE_MARGIN_PX) || ...
            (clusters(ci_a).cx >= P_W - HIND_EDGE_MARGIN_PX && ...
             clusters(ci_b).cx >= P_W - HIND_EDGE_MARGIN_PX);
        on_lr_edge = body_on_lr_edge || contacts_on_lr_edge;
        pair_dist = hypot(clusters(ci_a).cx - clusters(ci_b).cx, ...
            clusters(ci_a).cy - clusters(ci_b).cy);
        pair_fb_sep = abs(fb_a_raw - fb_b_raw);
        pair_close_enough = pair_dist <= HIND_PAIR_MAX_DIST_PX;
        edge_pair_plausible = on_lr_edge && ...
            pair_fb_sep <= SAME_GIRDLE_PAIR_MAX_FB_SEP_PX;

        both_hind = (fb_a_raw < hind_thresh) && (fb_b_raw < hind_thresh);

        if (pair_close_enough && both_hind) || edge_pair_plausible
            lr_a = (clusters(ci_a).cx - last_body_cx)*last_body_rax_x + ...
                   (clusters(ci_a).cy - last_body_cy)*last_body_rax_y;
            lr_b = (clusters(ci_b).cx - last_body_cx)*last_body_rax_x + ...
                   (clusters(ci_b).cy - last_body_cy)*last_body_rax_y;

            if lr_a < lr_b
                lbl_a = 3; lbl_b = 4;   % a=HL, b=HR
            else
                lbl_a = 4; lbl_b = 3;   % a=HR, b=HL
            end

            % Build forbidden set for same-paw minimum swing gate.
            forbidden_h = false(1,4);
            for fci = 1:numel(clusters)
                if clusters(fci).open, continue; end
                if ~cluster_is_valid_stance(clusters(fci), GAIT_MIN_STANCE_SEC)
                    continue;
                end
                flbl = clusters(fci).label;
                if isempty(flbl) || flbl == 0, continue; end
                if ~isempty(clusters(fci).close_time)
                    if (t - clusters(fci).close_time) < SWING_MIN_SEC
                        forbidden_h(flbl) = true;
                    end
                end
            end

            % Override pending or front-labelled; respect existing hind labels.
            % If the heuristic label is swing-forbidden, try the other side
            % (HL<->HR swap). If both are forbidden, fall back to IC-lock
            % (leave ic_label_done = false so IC-lock retries next frame).
            lbl_a_cur = clusters(ci_a).label;
            if isempty(lbl_a_cur) || lbl_a_cur == 1 || lbl_a_cur == 2
                eff_lbl_a = lbl_a;
                if forbidden_h(eff_lbl_a)
                    alt_a = 7 - eff_lbl_a;  % 3<->4 swap
                    if ~forbidden_h(alt_a)
                        eff_lbl_a = alt_a;
                    else
                        eff_lbl_a = 0;  % both forbidden
                    end
                end
                if eff_lbl_a > 0 && label_is_open_elsewhere(clusters, ci_a, eff_lbl_a, t, GAIT_MIN_STANCE_SEC)
                    alt_a = 7 - eff_lbl_a;  % 3<->4 swap
                    if ~forbidden_h(alt_a) && ...
                            ~label_is_open_elsewhere(clusters, ci_a, alt_a, t, GAIT_MIN_STANCE_SEC)
                        eff_lbl_a = alt_a;
                    else
                        eff_lbl_a = 0;
                    end
                end
                if eff_lbl_a > 0
                    clusters(ci_a).label         = eff_lbl_a;
                    clusters(ci_a).label_source  = 'hind_heuristic';
                    clusters(ci_a).ic_label_done = true;
                end
            end
            lbl_b_cur = clusters(ci_b).label;
            if isempty(lbl_b_cur) || lbl_b_cur == 1 || lbl_b_cur == 2
                eff_lbl_b = lbl_b;
                if forbidden_h(eff_lbl_b)
                    alt_b = 7 - eff_lbl_b;  % 3<->4 swap
                    if ~forbidden_h(alt_b)
                        eff_lbl_b = alt_b;
                    else
                        eff_lbl_b = 0;
                    end
                end
                if eff_lbl_b > 0 && label_is_open_elsewhere(clusters, ci_b, eff_lbl_b, t, GAIT_MIN_STANCE_SEC)
                    alt_b = 7 - eff_lbl_b;  % 3<->4 swap
                    if ~forbidden_h(alt_b) && ...
                            ~label_is_open_elsewhere(clusters, ci_b, alt_b, t, GAIT_MIN_STANCE_SEC)
                        eff_lbl_b = alt_b;
                    else
                        eff_lbl_b = 0;
                    end
                end
                if eff_lbl_b > 0
                    clusters(ci_b).label         = eff_lbl_b;
                    clusters(ci_b).label_source  = 'hind_heuristic';
                    clusters(ci_b).ic_label_done = true;
                end
            end
            hind_heuristic_fired = true;
        end
    end

    if last_body_reliable
        clusters = assign_open_girdles_by_lateral_rank(clusters, ...
            last_body_cx, last_body_cy, last_body_hax_x, last_body_hax_y, ...
            last_body_rax_x, last_body_rax_y, last_body_offset, ...
            SAME_GIRDLE_PAIR_MAX_FB_SEP_PX, FLIP_FORE_LATERAL_LABELS);
        clusters = reorder_open_same_girdle_pairs(clusters, last_body_cx, ...
            last_body_cy, last_body_hax_x, last_body_hax_y, ...
            last_body_rax_x, last_body_rax_y, SAME_GIRDLE_PAIR_MAX_FB_SEP_PX, ...
            FLIP_FORE_LATERAL_LABELS);
        clusters = resolve_open_duplicate_same_girdle_labels(clusters, ...
            last_body_cx, last_body_cy, last_body_rax_x, last_body_rax_y);
        clusters = assign_open_unlabeled_local_pairs(clusters, ...
            last_body_cx, last_body_cy, last_body_hax_x, last_body_hax_y, ...
            last_body_rax_x, last_body_rax_y, last_body_offset, ...
            SAME_GIRDLE_PAIR_MAX_FB_SEP_PX);
        clusters = mark_open_edge_artifact_noise_clusters(clusters, ...
            board_size * grid_cols, board_size * grid_rows);
        clusters = mark_open_isolated_noise_clusters(clusters);
        clusters = assign_remaining_open_unlabeled_noncompetitive(clusters, ...
            last_body_cx, last_body_cy, last_body_hax_x, last_body_hax_y, ...
            last_body_rax_x, last_body_rax_y, last_body_offset);
        clusters = resolve_open_labels_by_elimination(clusters);
        clusters = mark_open_severe_anatomy_noise_clusters(clusters);
    end

    % CLOSE stale clusters (liftoff)
    for ci2 = 1:numel(clusters)
        if ~clusters(ci2).open, continue; end
        if (frame_idx - clusters(ci2).last_frame) > CLUSTER_GAP_FRAMES
            clusters(ci2).open        = false;
            clusters(ci2).close_frame = frame_idx;
            clusters(ci2).close_time  = t;   % timestamp for swing-phase gate
            clusters(ci2).valid_stance = cluster_is_valid_stance( ...
                clusters(ci2), GAIT_MIN_STANCE_SEC);
            clusters(ci2).display_cx  = clusters(ci2).cx_sum / clusters(ci2).n_obs;
            clusters(ci2).display_cy  = clusters(ci2).cy_sum / clusters(ci2).n_obs;
            preserve_locked_square_label = strcmp(layout, 'square') && ...
                clusters(ci2).ic_label_done && ~isempty(clusters(ci2).label) && ...
                clusters(ci2).label > 0;
            preserve_hind_heuristic = strcmp(clusters(ci2).label_source, 'hind_heuristic') && ...
                ~isempty(clusters(ci2).label) && clusters(ci2).label >= 3;
            [final_lbl, final_src] = label_from_integrated_votes( ...
                clusters(ci2).quad_votes, IC_MIN_OVERLAP_PX);
            if final_lbl > 0 && ~preserve_hind_heuristic && ...
                    ~preserve_locked_square_label
                clusters(ci2).label = final_lbl;
                clusters(ci2).label_source = final_src;
                clusters(ci2).ic_label_done = true;
            end
            if isempty(clusters(ci2).label)
                clusters(ci2).label        = 0;
                clusters(ci2).label_source = 'no_label_evidence_at_LO_noise';
                clusters(ci2).ic_label_done = true;
            end
        end
    end

    % DISPLAY — no duplicate labels per frame
    best_by_label = cell(4,1);
    best_nobs     = zeros(4,1);

    for ci2 = 1:numel(clusters)
        lbl = clusters(ci2).label;
        if isempty(lbl) || lbl == 0, continue; end

        is_visible = false;
        if clusters(ci2).open
            is_visible = true;
        elseif DISPLAY_CLOSED_LABELS && ~isempty(clusters(ci2).close_frame)
            if (frame_idx - clusters(ci2).close_frame) <= DISPLAY_LINGER_FRAMES
                is_visible = true;
            end
        end
        if ~is_visible, continue; end

        if clusters(ci2).n_obs > best_nobs(lbl)
            best_nobs(lbl)     = clusters(ci2).n_obs;
            best_by_label{lbl} = ci2;
        end
    end

    if UPDATE_SEGMENTATION_DISPLAY
        handle_used = false(MAX_LABEL_HANDLES,1);
        lbl_count = 0;
        for lbl = 1:4
            if isempty(best_by_label{lbl}), continue; end
            ci2 = best_by_label{lbl};
            lbl_count = lbl_count + 1;
            if lbl_count > MAX_LABEL_HANDLES, break; end

            if clusters(ci2).open
                px = clusters(ci2).cx;
                py = clusters(ci2).cy;
            else
                px = clusters(ci2).display_cx;
                py = clusters(ci2).display_cy;
            end

            set(h_fp_labels(lbl_count), ...
                'Position',[px, py], ...
                'String',  label_names{lbl}, ...
                'Color',   label_colors{lbl}, ...
                'Visible', 'on');
            handle_used(lbl_count) = true;
        end
        for hi = 1:MAX_LABEL_HANDLES
            if ~handle_used(hi), set(h_fp_labels(hi),'Visible','off'); end
        end

        for hi = 1:MAX_DEBUG_CANDIDATES
            set(h_reject_marks(hi), 'Visible', 'off');
            set(h_reject_text(hi), 'Visible', 'off');
        end
        if DEBUG_FOOTPRINT_CANDIDATES
            n_reject_show = min(numel(reject_debug), MAX_DEBUG_CANDIDATES);
            for ri = 1:n_reject_show
                set(h_reject_marks(ri), 'XData', reject_debug(ri).x, ...
                    'YData', reject_debug(ri).y, 'Visible', 'on');
                set(h_reject_text(ri), 'Position', ...
                    [reject_debug(ri).x, reject_debug(ri).y + 3], ...
                    'String', reject_debug(ri).reason, 'Visible', 'on');
            end
        end

        % ---- Render geometry -------------------------------------------
        set(h_outline,   'XData',last_outline_x, 'YData',last_outline_y);
        set(h_axis_line, 'XData',last_axis_x,    'YData',last_axis_y);
        set(h_centroid,  'XData',last_cx,         'YData',last_cy);
        set(h_tail_tip,  'XData',last_tail_x,     'YData',last_tail_y);
        set(h_head_arrow,'XData',last_arrow_ox,   'YData',last_arrow_oy, ...
                         'UData',last_arrow_ux,   'VData',last_arrow_uy);
        for qi=1:4
            set(h_quads(qi),'XData',last_quad_bx{qi},'YData',last_quad_by{qi});
        end

        if is_standing
            set(h_standing_txt,'String',sprintf('STANDING  (%d / %d px)', ...
                round(current_area),max_mask_area),'Visible','on');
        else
            set(h_standing_txt,'Visible','off');
        end
        if near_edge
            set(h_edge_txt,'String','EDGE — geometry held','Visible','on');
        else
            set(h_edge_txt,'Visible','off');
        end
        if hind_heuristic_fired
            on_lr_edge_disp = ~isnan(last_body_cx) && ...
                (last_body_cx <= HIND_EDGE_MARGIN_PX || last_body_cx >= P_W - HIND_EDGE_MARGIN_PX);
            if on_lr_edge_disp
                set(h_hind_txt,'String','HIND×2 [L/R edge]','Visible','on');
            else
                set(h_hind_txt,'String','HIND×2 [FB proj]','Visible','on');
            end
        else
            set(h_hind_txt,'Visible','off');
        end

        n_open = sum(arrayfun(@(c) c.open, clusters));
        flags  = '';
        if is_standing,          flags = '  [STANDING]';        end
        if near_edge,            flags = [flags '  [EDGE]'];     end
        if anchor_fired,         flags = [flags '  [ANCHORED]']; end
        if hind_heuristic_fired, flags = [flags '  [HIND×2]'];   end
        if ~rat_is_moving,       flags = [flags '  [STATIONARY]']; end
        set(h_title,'String',sprintf('t = %.2f s%s', t, flags));
        set(h_status,'String',sprintf( ...
            'Speed: %.2fx  |  Open: %d  |  CoP: %.0fpx/s  |  %s  |  cam=%d', ...
            playback_speed, n_open, cop_speed, ...
            iif(rat_is_moving,'MOVING','STATIONARY'), cam_frame_count));
    end

    if SHOW_SEGMENTATION_FIGURE && isfinite(playback_speed) && ...
            playback_speed > 0 && time_idx < n_frames
        dt  = (all_times(time_idx+1)-t) / playback_speed;
        tgt = last_wall + dt;
        cur = toc;
        if cur < tgt, pause(tgt-cur); end
        last_wall = toc;
    end
    should_write_seg_video = SAVE_SEGMENTATION_VIDEO && ...
        ~isempty(seg_video_writer) && t >= seg_video_next_time;
    if should_write_seg_video
        drawnow limitrate;
        writeVideo(seg_video_writer, getframe(f));
        seg_video_frame_count = seg_video_frame_count + 1;
        if isinf(seg_video_next_time)
            seg_video_next_time = t + seg_video_sample_dt;
        else
            while seg_video_next_time <= t
                seg_video_next_time = seg_video_next_time + seg_video_sample_dt;
            end
        end
    elseif SHOW_SEGMENTATION_FIGURE
        drawnow limitrate nocallbacks;
    end

    progress_elapsed = toc(progress_tic);
    if time_idx == 1 || time_idx == n_frames || ...
            progress_elapsed - progress_last_print >= progress_print_interval_sec
        progress_last_print = progress_elapsed;
        progress_frac = time_idx / max(1, n_frames);
        progress_fps = time_idx / max(progress_elapsed, eps);
        remaining_frames = max(0, n_frames - time_idx);
        eta_sec = remaining_frames / max(progress_fps, eps);
        fprintf('[%s] %5.1f%%  frame %d/%d  t=%.2fs  elapsed=%s  ETA=%s  %.1f frames/s\n', ...
            progress_bar(progress_frac, progress_bar_width), ...
            100 * progress_frac, time_idx, n_frames, t, ...
            format_duration(progress_elapsed), format_duration(eta_sec), ...
            progress_fps);
    end
end

noise_clusters = close_open_noise_clusters(noise_clusters, frame_idx, t);
clusters = [clusters, noise_clusters];

if SAVE_SEGMENTATION_VIDEO && ~isempty(seg_video_writer)
    close_video_writer(seg_video_writer);
    seg_video_writer = [];
    fprintf('Saved segmentation video: %s (%d frames, sample_fps=%.1f, playback_fps=%.1f)\n', ...
        seg_video_path, seg_video_frame_count, SEGMENTATION_VIDEO_SAMPLE_FPS, ...
        SEGMENTATION_VIDEO_FPS);
end

fprintf('Raw peak-seed clusters: %d\n', numel(clusters));
if PRINT_RAW_CLUSTER_SUMMARY
    fprintf('\n--- Raw footstep fragment summary ---\n');
    for ci2 = 1:numel(clusters)
        lbl = clusters(ci2).label;
        if     isempty(lbl), lbl_str = 'pending';
        elseif lbl == 0,     lbl_str = 'noise';
        else,                lbl_str = label_names{lbl};
        end
        fprintf('  %3d | %-4s | %-28s | n=%3d | ctr=(%.1f,%.1f)\n', ...
            ci2, lbl_str, clusters(ci2).label_source, clusters(ci2).n_obs, ...
            clusters(ci2).display_cx, clusters(ci2).display_cy);
    end
end

if exist('segmentation_gait_cycle','file') == 2
    segmentation_gait_cycle(clusters, label_names, SWING_MIN_SEC, ...
        GAIT_MERGE_MAX_DIST_PX, false, GAIT_MIN_STANCE_SEC);
end

if EXPORT_FOOTSTEP_DYNAMICS
    raw_cluster_count = numel(clusters);
    export_clusters = group_clusters_before_refinement(clusters, ...
        PRE_REFINEMENT_GROUP_ENABLED, PRE_REFINEMENT_GROUP_MAX_GAP_SEC, ...
        PRE_REFINEMENT_GROUP_MAX_DIST_PX, ...
        PRE_REFINEMENT_CROSS_LABEL_DIST_PX, ...
        PRE_REFINEMENT_GROUP_MAX_SPAN_SEC);
    export_clusters = force_assign_grouped_clusters(export_clusters, ...
        FINAL_ASSIGN_MAX_DIST_PX);
    export_clusters = finalize_export_cluster_labels(export_clusters);
    % Fallback labels can be assigned only after live tracking has ended.
    % Apply the remote-weak-contact veto here as well, so these late labels
    % cannot bypass the physical outlier rule used during tracking.
    export_clusters = mark_remote_weak_export_outliers(export_clusters);
    export_clusters = finalize_export_cluster_labels(export_clusters);
    % A physical paw cannot occupy two spatially distinct contacts at the
    % same time.  Resolve any late export-stage duplicate paw labels after
    % all grouping and fallback labels have been finalized.
    export_clusters = enforce_overlapping_export_label_uniqueness(export_clusters);
    export_clusters = finalize_export_cluster_labels(export_clusters);
    assigned_count = sum(arrayfun(@(c)~isempty(c.label) && c.label > 0, ...
        export_clusters));
    noise_count = sum(arrayfun(@(c)~isempty(c.label) && c.label == 0, ...
        export_clusters));
    fprintf(['Pre-refinement grouping: %d raw clusters -> %d export clusters ', ...
        '(%d footprint, %d noise, 0 unassigned)\n'], raw_cluster_count, ...
        numel(export_clusters), assigned_count, noise_count);
    [footstep_events, clean_gait_events, export_params, export_source] = ...
        build_footstep_export(export_clusters, label_names, filename, fpath, ...
        video_cam1_path, PRESSURE_THRESH, MIN_CONTACT_AREA, CLUSTER_DIST_PX, ...
        CLUSTER_GAP_FRAMES, SWING_MIN_SEC, TACTILE_MM_PER_PX, ...
        GAIT_MERGE_MAX_DIST_MM, GAIT_MERGE_MAX_DIST_PX, GAIT_MIN_STANCE_SEC, ...
        DYNAMIC_PEAK_FRACTION, DYNAMIC_SEARCH_MAX_SEC, DYNAMIC_ROI_PAD_PX, ...
        DYNAMIC_ROI_MAX_SIZE_PX, DYNAMIC_SMOOTH_FRAMES, DYNAMIC_MIN_ON_FRAMES, ...
        DYNAMIC_OFF_FRAMES, DYNAMIC_STD_GROWTH_FACTOR, DYNAMIC_STD_GROWTH_MIN_PX, ...
        DYNAMIC_CENTROID_DRIFT_MAX_PX, ...
        DYNAMIC_SPLIT_VALLEY_FRACTION, DYNAMIC_SPLIT_MIN_PEAK_FRACTION, ...
        DYNAMIC_SPLIT_CENTROID_JUMP_PX, DYNAMIC_GLOBAL_DROPOUT_FRACTION, ...
        DYNAMIC_COMPONENT_MIN_AREA_PX, DYNAMIC_COMPONENT_OVERLAP_DILATE_PX, ...
        DYNAMIC_COMPONENT_MERGE_AREA_FACTOR, ...
        pressure_frames(:,:,1:frame_idx), pressure_times(1:frame_idx), ...
        pressure_frame_indices(1:frame_idx), tscam1_n, ...
        PRELABEL_MERGE_DIST_PX, PRELABEL_MERGE_MAX_AREA, ...
        PEAK_SEED_MIN_DENSITY, PEAK_SEED_MIN_MEAN_PRESSURE, ...
        PEAK_SEED_CANDIDATE_MODE, tac_fps, P_W, P_H);
    print_footstep_export_summary(footstep_events, clean_gait_events);
    export_params.raw_cluster_count = raw_cluster_count;
    export_params.export_cluster_count = numel(export_clusters);
    export_params.pre_refinement_group_enabled = PRE_REFINEMENT_GROUP_ENABLED;
    export_params.pre_refinement_group_max_gap_sec = PRE_REFINEMENT_GROUP_MAX_GAP_SEC;
    export_params.pre_refinement_group_max_dist_px = PRE_REFINEMENT_GROUP_MAX_DIST_PX;
    export_params.pre_refinement_cross_label_dist_px = PRE_REFINEMENT_CROSS_LABEL_DIST_PX;
    export_params.pre_refinement_group_max_span_sec = PRE_REFINEMENT_GROUP_MAX_SPAN_SEC;
    export_params.final_assign_max_dist_px = FINAL_ASSIGN_MAX_DIST_PX;
    export_params.prelabel_merge_edge_gap_px = PRELABEL_MERGE_EDGE_GAP_PX;
    export_params.prelabel_merge_dilate_radius_px = PRELABEL_MERGE_DILATE_RADIUS_PX;
    export_params.prelabel_merge_seam_max_area = PRELABEL_MERGE_SEAM_MAX_AREA;
    export_params.prelabel_split_multipeak = PRELABEL_SPLIT_MULTIPEAK;
    export_params.prelabel_split_min_area = PRELABEL_SPLIT_MIN_AREA;
    export_params.prelabel_split_min_peak_dist_px = PRELABEL_SPLIT_MIN_PEAK_DIST_PX;
    export_params.prelabel_split_min_prominence = PRELABEL_SPLIT_MIN_PROMINENCE;
    export_params.assigned_export_cluster_count = assigned_count;
    pressure_movie_frames = pressure_frames(:,:,1:frame_idx);
    pressure_movie_times = pressure_times(1:frame_idx);
    pressure_movie_frame_indices = pressure_frame_indices(1:frame_idx);

    body_axis_trace = struct();
    body_axis_trace.time        = body_axis_log_t(1:frame_idx);
    body_axis_trace.cx          = body_axis_log_cx(1:frame_idx);
    body_axis_trace.cy          = body_axis_log_cy(1:frame_idx);
    body_axis_trace.head_ax_x   = body_axis_log_hax_x(1:frame_idx);
    body_axis_trace.head_ax_y   = body_axis_log_hax_y(1:frame_idx);
    body_axis_trace.right_ax_x  = body_axis_log_rax_x(1:frame_idx);
    body_axis_trace.right_ax_y  = body_axis_log_rax_y(1:frame_idx);
    body_axis_trace.offset      = body_axis_log_offset(1:frame_idx);
    body_axis_trace.reliable    = body_axis_log_reliable(1:frame_idx);

    export_name = sprintf('%s_peak_seed_footstep_dynamics.mat', erase(filename, '.mat'));
    export_path = fullfile(output_dir, export_name);
    save(export_path, 'footstep_events', 'clean_gait_events', ...
        'export_params', 'export_source', 'pressure_movie_frames', ...
        'pressure_movie_times', 'pressure_movie_frame_indices', ...
        'body_axis_trace', '-v7.3');
    fprintf('Saved footstep dynamics: %s\n', export_path);
end

% CALLBACKS
function cb_pause(src,~)
    panel=src.Parent; cs=get(panel,'UserData');
    cs.is_paused=~cs.is_paused; set(panel,'UserData',cs);
    if cs.is_paused, set(src,'String','Resume','BackgroundColor',[0.6 0.2 0.2]);
    else,            set(src,'String','Pause', 'BackgroundColor',[0.3 0.3 0.3]); end
end

function cb_speed(src,~)
    panel=src.Parent; cs=get(panel,'UserData');
    cs.playback_speed=src.UserData; set(panel,'UserData',cs);
    for k=1:numel(panel.Children)
        ch=panel.Children(k); ud=get(ch,'UserData');
        if strcmp(get(ch,'Style'),'pushbutton')&&isnumeric(ud)&&~isempty(ud)
            if ud==cs.playback_speed
                set(ch,'BackgroundColor',[0.2 0.5 0.8],'ForegroundColor',[1 1 1]);
            else
                set(ch,'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.8 0.8 0.8]);
            end
        end
    end
end

% LOCAL FUNCTIONS
function predictions=load_tailbase_predictions(path_value)
    predictions = struct('available', false, 'frame_index', [], ...
        'x', [], 'y', [], 'confidence', []);
    if isempty(path_value) || ~exist(path_value, 'file')
        return;
    end
    T = readtable(path_value, 'TextType', 'string', ...
        'VariableNamingRule', 'preserve');
    names = string(T.Properties.VariableNames);
    if ~all(ismember(["frame_index", "tailbase_x_px", "tailbase_y_px"], names))
        warning('Tailbase prediction CSV missing required columns: %s', ...
            path_value);
        return;
    end
    predictions.available = true;
    predictions.frame_index = double(T.frame_index);
    predictions.x = double(T.tailbase_x_px);
    predictions.y = double(T.tailbase_y_px);
    if ismember("tailbase_confidence", names)
        predictions.confidence = double(T.tailbase_confidence);
    else
        predictions.confidence = nan(height(T), 1);
    end
    fprintf('Loaded tailbase predictions: %s (%d frames)\n', ...
        path_value, height(T));
end

function [x,y,confidence]=tailbase_prediction_for_frame(predictions,frame_index)
    x = NaN; y = NaN; confidence = NaN;
    if ~isfield(predictions, 'available') || ~predictions.available
        return;
    end
    match = find(predictions.frame_index == frame_index, 1, 'first');
    if isempty(match)
        return;
    end
    x = predictions.x(match);
    y = predictions.y(match);
    confidence = predictions.confidence(match);
end

function highlight_speed_btn(btns,vals,current_speed)
    for k=1:numel(btns)
        if vals(k)==current_speed
            set(btns(k),'BackgroundColor',[0.2 0.5 0.8],'ForegroundColor',[1 1 1]);
        else
            set(btns(k),'BackgroundColor',[0.25 0.25 0.25],'ForegroundColor',[0.8 0.8 0.8]);
        end
    end
end

function img=apply_transform(img,type)
    switch type
        case 'rot180', img=rot90(img,2);
        case 'rot90',  img=rot90(img,1);
        case 'rot270', img=rot90(img,3);
        case 'fliplr', img=fliplr(img);
        case 'flipud', img=flipud(img);
    end
end

function [r,c]=index_to_coords(idx)
    idx = double(idx);
    r = nan(size(idx));
    c = nan(size(idx));
    left_half = idx < 2048;
    r(left_half) = floor(idx(left_half)/32)+1;
    c(left_half) = mod(idx(left_half),32)+1;
    right_half = ~left_half;
    r(right_half) = floor((idx(right_half)-2048)/32)+1;
    c(right_half) = mod(idx(right_half)-2048,32)+33;
end

function out=iif(cond,a,b)
    % Inline if: out = a when cond is true, b otherwise.
    if cond, out=a; else, out=b; end
end

function s=progress_bar(frac,width)
    frac = max(0, min(1, frac));
    n_done = floor(frac * width);
    s = [repmat('#', 1, n_done), repmat('-', 1, width - n_done)];
end

function s=format_duration(seconds_value)
    if ~isfinite(seconds_value)
        s = 'unknown';
        return;
    end
    seconds_value = max(0, seconds_value);
    hh = floor(seconds_value / 3600);
    mm = floor(mod(seconds_value, 3600) / 60);
    ss = floor(mod(seconds_value, 60));
    if hh > 0
        s = sprintf('%dh%02dm%02ds', hh, mm, ss);
    elseif mm > 0
        s = sprintf('%dm%02ds', mm, ss);
    else
        s = sprintf('%ds', ss);
    end
end

function close_video_writer(writer)
    try
        if ~isempty(writer)
            close(writer);
        end
    catch
    end
end

function props=annotate_source_component_count(props,count_value)
    for pi = 1:numel(props)
        props(pi).SourceComponentCount = count_value;
    end
end

function merged_props=merge_nearby_footprint_props(fp_props,pressure_img, ...
        merge_dist_px,edge_gap_px,dilate_radius_px,max_merged_area, ...
        seam_max_merged_area,board_size_px)
    if numel(fp_props) <= 1
        merged_props = fp_props;
        return;
    end

    n = numel(fp_props);
    parent = 1:n;
    for i = 1:n
        for j = i+1:n
            combined_area = fp_props(i).Area + fp_props(j).Area;
            near_seam = components_near_board_seam(fp_props(i), fp_props(j), ...
                size(pressure_img), board_size_px, edge_gap_px);
            area_limit = max_merged_area;
            if near_seam
                area_limit = max(area_limit, seam_max_merged_area);
            end
            if combined_area > area_limit
                continue;
            end
            d = hypot(fp_props(i).Centroid(1)-fp_props(j).Centroid(1), ...
                fp_props(i).Centroid(2)-fp_props(j).Centroid(2));
            edge_gap = component_edge_gap_px(fp_props(i), fp_props(j), ...
                size(pressure_img));
            dilate_touch = components_touch_after_dilation(fp_props(i), ...
                fp_props(j), size(pressure_img), dilate_radius_px);
            if d <= merge_dist_px || edge_gap <= edge_gap_px || ...
                    dilate_touch || near_seam
                parent = union_sets(parent, i, j);
            end
        end
    end

    roots = arrayfun(@(x)find_root(parent,x), 1:n);
    unique_roots = unique(roots, 'stable');
    merged_props = struct('Area',{},'Centroid',{},'PixelIdxList',{}, ...
        'SourceComponentCount',{});
    for ri = 1:numel(unique_roots)
        members = find(roots == unique_roots(ri));
        pix = vertcat(fp_props(members).PixelIdxList);
        pix = unique(pix);
        vals = double(pressure_img(pix));
        [rows, cols] = ind2sub(size(pressure_img), pix);
        if sum(vals) > 0
            cx = sum(cols .* vals) / sum(vals);
            cy = sum(rows .* vals) / sum(vals);
        else
            cx = mean(cols);
            cy = mean(rows);
        end
        merged_props(ri).Area = numel(pix); %#ok<AGROW>
        merged_props(ri).Centroid = [cx, cy]; %#ok<AGROW>
        merged_props(ri).PixelIdxList = pix; %#ok<AGROW>
        merged_props(ri).SourceComponentCount = sum([fp_props(members).SourceComponentCount]);
    end
end

function print_prelabel_merge_debug(frame_idx,before_props,after_props, ...
        pressure_img,merge_dist_px,edge_gap_px,dilate_radius_px, ...
        max_merged_area,seam_max_merged_area,board_size_px)
    fprintf('prelabel f%d merge: %d -> %d props, counts=[%s]\n', ...
        frame_idx, numel(before_props), numel(after_props), ...
        format_numeric_row([after_props.SourceComponentCount]));
    for i = 1:numel(before_props)
        for j = i+1:numel(before_props)
            combined_area = before_props(i).Area + before_props(j).Area;
            d = hypot(before_props(i).Centroid(1)-before_props(j).Centroid(1), ...
                before_props(i).Centroid(2)-before_props(j).Centroid(2));
            rect_gap = component_bbox_gap_px(before_props(i), before_props(j), ...
                size(pressure_img));
            edge_gap = component_edge_gap_px(before_props(i), before_props(j), ...
                size(pressure_img));
            dilate_touch = components_touch_after_dilation(before_props(i), ...
                before_props(j), size(pressure_img), dilate_radius_px);
            near_seam = components_near_board_seam(before_props(i), ...
                before_props(j), size(pressure_img), board_size_px, edge_gap_px);
            area_limit = max_merged_area;
            if near_seam
                area_limit = max(area_limit, seam_max_merged_area);
            end
            merge_allowed = combined_area <= area_limit && ...
                (d <= merge_dist_px || edge_gap <= edge_gap_px || ...
                dilate_touch || near_seam);
            if rect_gap <= 12 || d <= 25
                fprintf(['  pair %d-%d area=%d+%d=%d d=%.2f ', ...
                    'bbox_gap=%.2f edge_gap=%.2f dilate=%d seam=%d ', ...
                    'area_lim=%d merge=%d\n'], ...
                    i, j, before_props(i).Area, before_props(j).Area, ...
                    combined_area, d, rect_gap, edge_gap, dilate_touch, ...
                    near_seam, area_limit, merge_allowed);
            end
        end
    end
end

function s=format_numeric_row(values)
    if isempty(values)
        s = '';
    else
        s = strtrim(sprintf('%g ', values));
    end
end

function gap=component_edge_gap_px(prop_a,prop_b,img_size)
    [ra, ca] = ind2sub(img_size, prop_a.PixelIdxList);
    [rb, cb] = ind2sub(img_size, prop_b.PixelIdxList);
    if isempty(ra) || isempty(rb)
        gap = Inf;
        return;
    end
    bbox_a = [min(ca), max(ca), min(ra), max(ra)];
    bbox_b = [min(cb), max(cb), min(rb), max(rb)];
    if bbox_rect_gap_px(bbox_a, bbox_b) > 8
        gap = Inf;
        return;
    end
    dx = ca(:) - cb(:)';
    dy = ra(:) - rb(:)';
    gap = sqrt(min(dx(:).^2 + dy(:).^2));
end

function tf=components_touch_after_dilation(prop_a,prop_b,img_size,radius_px)
    tf = false;
    if radius_px <= 0
        return;
    end
    [ra, ca] = ind2sub(img_size, prop_a.PixelIdxList);
    [rb, cb] = ind2sub(img_size, prop_b.PixelIdxList);
    if isempty(ra) || isempty(rb)
        return;
    end

    pad = ceil(radius_px) + 1;
    r1 = max(1, min([ra; rb]) - pad);
    r2 = min(img_size(1), max([ra; rb]) + pad);
    c1 = max(1, min([ca; cb]) - pad);
    c2 = min(img_size(2), max([ca; cb]) + pad);

    mask_a = false(r2-r1+1, c2-c1+1);
    mask_b = false(size(mask_a));
    mask_a(sub2ind(size(mask_a), ra-r1+1, ca-c1+1)) = true;
    mask_b(sub2ind(size(mask_b), rb-r1+1, cb-c1+1)) = true;
    se = strel('disk', round(radius_px));
    overlap = imdilate(mask_a, se) & imdilate(mask_b, se);
    tf = any(overlap(:));
end

function tf=components_near_board_seam(prop_a,prop_b,img_size,board_size_px, ...
        seam_gap_px)
    tf = false;
    [ra, ca] = ind2sub(img_size, prop_a.PixelIdxList);
    [rb, cb] = ind2sub(img_size, prop_b.PixelIdxList);
    if isempty(ra) || isempty(rb) || board_size_px <= 0
        return;
    end

    bbox_a = [min(ca), max(ca), min(ra), max(ra)];
    bbox_b = [min(cb), max(cb), min(rb), max(rb)];
    max_gap = max(1, seam_gap_px);

    vertical_seams = board_size_px:board_size_px:(img_size(2)-1);
    for sx = vertical_seams
        a_left = bbox_a(2) <= sx && sx - bbox_a(2) <= max_gap;
        b_right = bbox_b(1) >= sx+1 && bbox_b(1) - (sx+1) <= max_gap;
        b_left = bbox_b(2) <= sx && sx - bbox_b(2) <= max_gap;
        a_right = bbox_a(1) >= sx+1 && bbox_a(1) - (sx+1) <= max_gap;
        if ((a_left && b_right) || (b_left && a_right)) && ...
                interval_gap_px(bbox_a(3), bbox_a(4), bbox_b(3), bbox_b(4)) <= max_gap
            tf = true;
            return;
        end
    end

    horizontal_seams = board_size_px:board_size_px:(img_size(1)-1);
    for sy = horizontal_seams
        a_top = bbox_a(4) <= sy && sy - bbox_a(4) <= max_gap;
        b_bottom = bbox_b(3) >= sy+1 && bbox_b(3) - (sy+1) <= max_gap;
        b_top = bbox_b(4) <= sy && sy - bbox_b(4) <= max_gap;
        a_bottom = bbox_a(3) >= sy+1 && bbox_a(3) - (sy+1) <= max_gap;
        if ((a_top && b_bottom) || (b_top && a_bottom)) && ...
                interval_gap_px(bbox_a(1), bbox_a(2), bbox_b(1), bbox_b(2)) <= max_gap
            tf = true;
            return;
        end
    end
end

function gap=interval_gap_px(a1,a2,b1,b2)
    gap = max([b1 - a2 - 1, a1 - b2 - 1, 0]);
end

function gap=component_bbox_gap_px(prop_a,prop_b,img_size)
    [ra, ca] = ind2sub(img_size, prop_a.PixelIdxList);
    [rb, cb] = ind2sub(img_size, prop_b.PixelIdxList);
    if isempty(ra) || isempty(rb)
        gap = Inf;
        return;
    end
    bbox_a = [min(ca), max(ca), min(ra), max(ra)];
    bbox_b = [min(cb), max(cb), min(rb), max(rb)];
    gap = bbox_rect_gap_px(bbox_a, bbox_b);
end

function gap=bbox_rect_gap_px(bbox_a,bbox_b)
    x_gap = max([bbox_b(1) - bbox_a(2) - 1, bbox_a(1) - bbox_b(2) - 1, 0]);
    y_gap = max([bbox_b(3) - bbox_a(4) - 1, bbox_a(3) - bbox_b(4) - 1, 0]);
    gap = hypot(x_gap, y_gap);
end

function split_props=split_multipeak_footprint_props(fp_props,pressure_img, ...
        split_enabled,min_contact_area,min_split_area,min_peak_dist_px, ...
        min_peak_prominence)
    if ~split_enabled || isempty(fp_props)
        split_props = fp_props;
        return;
    end

    split_props = struct('Area',{},'Centroid',{},'PixelIdxList',{}, ...
        'SourceComponentCount',{});
    for pi = 1:numel(fp_props)
        prop = fp_props(pi);
        if prop.Area < max(min_split_area, 2 * min_contact_area) || ...
                prop.SourceComponentCount > 1
            split_props(end+1) = prop; %#ok<AGROW>
            continue;
        end

        parts = split_one_multipeak_component(prop, pressure_img, ...
            min_contact_area, min_peak_dist_px, min_peak_prominence);
        for si = 1:numel(parts)
            split_props(end+1) = parts(si); %#ok<AGROW>
        end
    end
end

function parts=split_one_multipeak_component(prop,pressure_img,min_contact_area, ...
        min_peak_dist_px,min_peak_prominence)
    parts = prop;
    [rows, cols] = ind2sub(size(pressure_img), prop.PixelIdxList);
    y1 = min(rows); y2 = max(rows);
    x1 = min(cols); x2 = max(cols);
    crop = double(pressure_img(y1:y2, x1:x2));
    mask = false(size(crop));
    local_rows = rows - y1 + 1;
    local_cols = cols - x1 + 1;
    mask(sub2ind(size(mask), local_rows, local_cols)) = true;
    if bwconncomp(mask).NumObjects > 1
        return;
    end

    if exist('imgaussfilt', 'file') == 2
        smooth = imgaussfilt(crop, 0.7);
    else
        smooth = crop;
    end
    smooth(~mask) = 0;

    seed_mask = imextendedmax(smooth, min_peak_prominence) & mask;
    seed_mask = suppress_nearby_peak_seeds(seed_mask, smooth, min_peak_dist_px);
    seed_cc = bwconncomp(seed_mask);
    if seed_cc.NumObjects < 2
        return;
    end

    imposed = imimposemin(-smooth, seed_mask | ~mask);
    L = watershed(imposed);
    L(~mask) = 0;
    labels = unique(L(mask));
    labels(labels == 0) = [];

    candidate_parts = struct('Area',{},'Centroid',{},'PixelIdxList',{}, ...
        'SourceComponentCount',{});
    for li = 1:numel(labels)
        local_pix = find(L == labels(li));
        if numel(local_pix) < min_contact_area
            continue;
        end
        [lr, lc] = ind2sub(size(mask), local_pix);
        global_rows = lr + y1 - 1;
        global_cols = lc + x1 - 1;
        global_pix = sub2ind(size(pressure_img), global_rows, global_cols);
        vals = double(pressure_img(global_pix));
        if sum(vals) > 0
            cx = sum(global_cols .* vals) / sum(vals);
            cy = sum(global_rows .* vals) / sum(vals);
        else
            cx = mean(global_cols);
            cy = mean(global_rows);
        end
        candidate_parts(end+1).Area = numel(global_pix); %#ok<AGROW>
        candidate_parts(end).Centroid = [cx, cy];
        candidate_parts(end).PixelIdxList = global_pix(:);
        candidate_parts(end).SourceComponentCount = 1;
    end

    split_area = sum([candidate_parts.Area]);
    if numel(candidate_parts) < 2 || split_area < min_contact_area || ...
            split_area < 0.6 * prop.Area
        return;
    end
    parts = candidate_parts;
end

function seed_mask=suppress_nearby_peak_seeds(seed_mask,pressure_img,min_dist_px)
    seed_cc = bwconncomp(seed_mask);
    if seed_cc.NumObjects <= 1
        return;
    end
    stats = regionprops(seed_cc, pressure_img, 'WeightedCentroid', 'MaxIntensity');
    keep = true(seed_cc.NumObjects, 1);
    for i = 1:seed_cc.NumObjects
        if ~keep(i)
            continue;
        end
        for j = i+1:seed_cc.NumObjects
            if ~keep(j)
                continue;
            end
            d = hypot(stats(i).WeightedCentroid(1) - stats(j).WeightedCentroid(1), ...
                stats(i).WeightedCentroid(2) - stats(j).WeightedCentroid(2));
            if d <= min_dist_px
                if stats(i).MaxIntensity >= stats(j).MaxIntensity
                    keep(j) = false;
                else
                    keep(i) = false;
                    break;
                end
            end
        end
    end
    remove_idx = find(~keep);
    for ri = 1:numel(remove_idx)
        seed_mask(seed_cc.PixelIdxList{remove_idx(ri)}) = false;
    end
end

function parent=union_sets(parent,a,b)
    ra = find_root(parent,a);
    rb = find_root(parent,b);
    if ra ~= rb
        parent(parent == rb) = ra;
    end
end

function r=find_root(parent,x)
    r = x;
    while parent(r) ~= r
        r = parent(r);
    end
end

function [tf,label]=component_body_mask_label(prop,quad_masks,quad_ready, ...
        body_reliable)
%COMPONENT_BODY_MASK_LABEL Return the quadrant containing a pressure blob.
% A nonzero result is used as a hard footprint override: the projected rat
% mask is the experiment-specific definition of where real contacts occur.
    tf = false;
    label = 0;
    if ~quad_ready || ~body_reliable || isempty(prop.PixelIdxList)
        return;
    end

    votes = zeros(1,4);
    for qi = 1:min(4, numel(quad_masks))
        mask = quad_masks{qi};
        if isempty(mask)
            continue;
        end
        if islogical(mask)
            votes(qi) = sum(mask(prop.PixelIdxList));
        else
            votes(qi) = sum(ismember(prop.PixelIdxList, mask));
        end
    end
    [best_vote,label] = max(votes);
    tf = best_vote > 0;
    if ~tf
        label = 0;
    end
end

function [tf,reason]=is_peak_seed_candidate(prop,pressure_img,min_density, ...
        min_mean_pressure,candidate_mode)
    pix = prop.PixelIdxList;
    [rows, cols] = ind2sub(size(pressure_img), pix);
    bbox_area = (max(cols) - min(cols) + 1) * (max(rows) - min(rows) + 1);
    density = prop.Area / max(1, bbox_area);
    mean_pressure = mean(double(pressure_img(pix)));
    if strcmpi(candidate_mode, 'binary')
        tf = true;
        reason = sprintf('binary density %.2f mean %.0f', density, ...
            mean_pressure);
        return;
    end
    tf = density >= min_density && mean_pressure >= min_mean_pressure;
    if ~tf && density < min_density
        reason = sprintf('sparse %.2f', density);
    elseif ~tf
        reason = sprintf('mean %.0f', mean_pressure);
    else
        reason = 'ok';
    end
end

function reason=candidate_reject_reason(prop,min_area,peak_reason,is_tail_candidate)
    if prop.Area < min_area
        reason = sprintf('area %d', prop.Area);
    elseif is_tail_candidate
        reason = 'tail';
    else
        reason = peak_reason;
    end
end

function [axis_x,axis_y,prev_x,prev_y,pending_x,pending_y,pending_count, ...
        last_axis_frame,flip_accepted]=keep_axis_sign_with_hysteresis( ...
        raw_x,raw_y,prev_x,prev_y,pending_x,pending_y,pending_count, ...
        last_axis_frame,current_frame,confirm_frames)
    flip_accepted = false;
    [axis_x, axis_y] = normalize_axis(raw_x, raw_y);
    if isnan(axis_x)
        return;
    end

    if ~isnan(last_axis_frame)
        frame_jump = abs(current_frame - last_axis_frame);
        if frame_jump > max(2, confirm_frames * 3)
            prev_x = NaN; prev_y = NaN;
            pending_x = NaN; pending_y = NaN;
            pending_count = 0;
        end
    end
    last_axis_frame = current_frame;

    [prev_x, prev_y] = normalize_axis(prev_x, prev_y);
    if isnan(prev_x)
        pending_x = NaN; pending_y = NaN;
        pending_count = 0;
        prev_x = axis_x; prev_y = axis_y;
        return;
    end

    if axis_x*prev_x + axis_y*prev_y >= 0
        pending_x = NaN; pending_y = NaN;
        pending_count = 0;
        prev_x = axis_x; prev_y = axis_y;
        return;
    end

    new_x = axis_x;
    new_y = axis_y;
    [pending_x, pending_y] = normalize_axis(pending_x, pending_y);
    if isnan(pending_x) || (new_x*pending_x + new_y*pending_y) < cosd(45)
        pending_x = new_x;
        pending_y = new_y;
        pending_count = 1;
    else
        [pending_x, pending_y] = normalize_axis(pending_x + new_x, ...
            pending_y + new_y);
        pending_count = pending_count + 1;
    end

    if pending_count >= confirm_frames
        axis_x = new_x;
        axis_y = new_y;
        prev_x = axis_x;
        prev_y = axis_y;
        pending_x = NaN; pending_y = NaN;
        pending_count = 0;
        flip_accepted = true;
    else
        axis_x = -new_x;
        axis_y = -new_y;
    end
end

function [x,y]=normalize_axis(x,y)
    n = sqrt(x^2 + y^2);
    if isnan(n) || n < 1e-9
        x = NaN; y = NaN;
    else
        x = x / n;
        y = y / n;
    end
end

function clusters=merge_duplicate_open_clusters(clusters,merge_dist_px, ...
        body_cx,body_cy,head_ax_x,head_ax_y,body_reliable,proximal_split_px)
    open_ci = find(arrayfun(@(c)c.open, clusters));
    if numel(open_ci) <= 1
        return;
    end

    for ia = 1:numel(open_ci)
        ci_a = open_ci(ia);
        if ci_a > numel(clusters) || ~clusters(ci_a).open
            continue;
        end
        for ib = ia+1:numel(open_ci)
            ci_b = open_ci(ib);
            if ci_b > numel(clusters) || ~clusters(ci_b).open
                continue;
            end
            d = hypot(clusters(ci_a).cx - clusters(ci_b).cx, ...
                clusters(ci_a).cy - clusters(ci_b).cy);
            if d > merge_dist_px
                continue;
            end
            if xor(is_explicit_noise_cluster(clusters(ci_a)), ...
                    is_explicit_noise_cluster(clusters(ci_b)))
                continue;
            end

            if clusters(ci_a).start_time <= clusters(ci_b).start_time
                old_ci = ci_a;
                new_ci = ci_b;
            else
                old_ci = ci_b;
                new_ci = ci_a;
            end
            if is_proximal_new_contact(clusters(old_ci), clusters(new_ci).cx, ...
                    clusters(new_ci).cy, body_cx, body_cy, head_ax_x, ...
                    head_ax_y, body_reliable, proximal_split_px)
                continue;
            end

            keep = ci_a;
            drop = ci_b;
            if clusters(ci_b).n_obs > clusters(ci_a).n_obs
                keep = ci_b;
                drop = ci_a;
            end
            clusters(keep) = combine_open_clusters(clusters(keep), clusters(drop));
            clusters(drop).open = false;
            clusters(drop).label = 0;
            clusters(drop).label_source = 'duplicate_cluster_merged';
            clusters(drop).ic_label_done = true;
            clusters(drop).valid_stance = false;
            clusters(drop).close_frame = clusters(keep).last_frame;
            clusters(drop).close_time = clusters(keep).last_time;
        end
    end
end

function tf=is_proximal_new_contact(old_cluster,new_x,new_y,body_cx,body_cy, ...
        head_ax_x,head_ax_y,body_reliable,proximal_split_px)
    tf = false;
    if ~body_reliable || any(isnan([new_x; new_y; body_cx; body_cy; ...
            head_ax_x; head_ax_y]))
        return;
    end
    if old_cluster.n_obs < 2
        return;
    end

    old_x = old_cluster.cx;
    old_y = old_cluster.cy;
    old_fb = (old_x - body_cx)*head_ax_x + (old_y - body_cy)*head_ax_y;
    new_fb = (new_x - body_cx)*head_ax_x + (new_y - body_cy)*head_ax_y;
    shift_toward_tail = old_fb - new_fb;

    old_body_dist = hypot(old_x - body_cx, old_y - body_cy);
    new_body_dist = hypot(new_x - body_cx, new_y - body_cy);
    shift_toward_body = old_body_dist - new_body_dist;

    tf = shift_toward_tail >= proximal_split_px || ...
        shift_toward_body >= proximal_split_px;
end

function a=combine_open_clusters(a,b)
    old_n = a.n_obs;
    new_n = old_n + b.n_obs;
    a.cx_sum = a.cx_sum + b.cx_sum;
    a.cy_sum = a.cy_sum + b.cy_sum;
    a.n_obs = new_n;
    a.cx = a.cx_sum / max(1, new_n);
    a.cy = a.cy_sum / max(1, new_n);
    a.display_cx = a.cx;
    a.display_cy = a.cy;
    if b.start_frame < a.start_frame
        a.start_frame = b.start_frame;
        a.start_time = b.start_time;
        a.start_cx = b.start_cx;
        a.start_cy = b.start_cy;
    end
    if b.last_frame > a.last_frame
        a.last_frame = b.last_frame;
        a.last_time = b.last_time;
    end
    a.quad_votes = a.quad_votes + b.quad_votes;
    a.dynamics = concatenate_dynamics(a.dynamics, b.dynamics);

    if isempty(a.label) || a.label == 0
        a.label = b.label;
        a.label_source = b.label_source;
        a.ic_label_done = b.ic_label_done;
    end
end

function dyn=concatenate_dynamics(dyn,extra_dyn)
    fields = fieldnames(dyn);
    for fi = 1:numel(fields)
        f = fields{fi};
        if isfield(extra_dyn, f) && ~isempty(extra_dyn.(f))
            dyn.(f) = [dyn.(f)(:); extra_dyn.(f)(:)];
        end
    end
    if isfield(dyn, 'time') && ~isempty(dyn.time)
        [~, order] = sort(dyn.time);
        for fi = 1:numel(fields)
            f = fields{fi};
            if numel(dyn.(f)) == numel(order)
                dyn.(f) = dyn.(f)(order);
            end
        end
    end
end

function grouped=group_clusters_before_refinement(clusters,enabled,max_gap_sec, ...
        max_dist_px,cross_label_dist_px,max_span_sec)
    grouped = clusters;
    if ~enabled || numel(clusters) <= 1
        grouped = ensure_member_cluster_ids(grouped);
        return;
    end

    clusters = ensure_member_cluster_ids(clusters);
    start_times = [clusters.start_time];
    start_times(isnan(start_times)) = Inf;
    [~, order] = sort(start_times);
    clusters = clusters(order);

    grouped = repmat(clusters(1), 0, 1);
    used = false(numel(clusters), 1);
    for i = 1:numel(clusters)
        if used(i)
            continue;
        end
        g = clusters(i);
        used(i) = true;

        changed = true;
        while changed
            changed = false;
            for j = i+1:numel(clusters)
                if used(j)
                    continue;
                end
                if clusters_are_pre_refinement_duplicates(g, clusters(j), ...
                        max_gap_sec, max_dist_px, cross_label_dist_px, ...
                        max_span_sec)
                    g = combine_grouped_clusters(g, clusters(j));
                    used(j) = true;
                    changed = true;
                end
            end
        end
        grouped(end+1,1) = g; %#ok<AGROW>
    end

    [~, out_order] = sort([grouped.start_time]);
    grouped = grouped(out_order);
end

function clusters=ensure_member_cluster_ids(clusters)
    for i = 1:numel(clusters)
        if ~isfield(clusters, 'member_cluster_ids') || ...
                isempty(clusters(i).member_cluster_ids)
            clusters(i).member_cluster_ids = i;
        end
    end
end

function tf=clusters_are_pre_refinement_duplicates(a,b,max_gap_sec,max_dist_px, ...
        cross_label_dist_px,max_span_sec)
    tf = false;

    a_end = cluster_end_time_for_export(a);
    b_end = cluster_end_time_for_export(b);
    if any(isnan([a.start_time, a_end, b.start_time, b_end]))
        return;
    end
    combined_span = max(a_end, b_end) - min(a.start_time, b.start_time);
    if combined_span > max_span_sec
        return;
    end
    gap = max(0, max(a.start_time, b.start_time) - min(a_end, b_end));
    if gap > max_gap_sec
        return;
    end

    dist = hypot(a.display_cx - b.display_cx, a.display_cy - b.display_cy);
    a_is_noise = is_explicit_noise_cluster(a);
    b_is_noise = is_explicit_noise_cluster(b);
    if xor(a_is_noise, b_is_noise)
        % A weak onset/offset fragment belongs to the same footprint only
        % when it is immediately adjacent and spatially coincident.  This
        % recovers real paw contacts below the seed area threshold without
        % absorbing unrelated small artifacts into a paw event.
        noise_to_paw_max_gap_sec = min(0.04, max_gap_sec);
        noise_to_paw_max_dist_px = min(8, max_dist_px);
        tf = gap <= noise_to_paw_max_gap_sec && dist <= noise_to_paw_max_dist_px;
        return;
    end
    a_has_label = ~isempty(a.label) && a.label > 0;
    b_has_label = ~isempty(b.label) && b.label > 0;
    if a_has_label && b_has_label && a.label == b.label
        tf = dist <= max_dist_px;
    elseif xor(a_has_label, b_has_label)
        tf = dist <= max_dist_px;
    elseif a_has_label && b_has_label
        % Same physical pressure component can be relabeled when body-axis
        % heuristics drift. Only merge label conflicts when almost identical
        % in space and overlapping/nearby in time.
        tf = dist <= cross_label_dist_px;
    else
        tf = dist <= cross_label_dist_px;
    end
end

function a=combine_grouped_clusters(a,b)
    original_label = a.label;
    promoted_noise_fragment = xor(is_explicit_noise_cluster(a), ...
        is_explicit_noise_cluster(b));
    chosen_label = choose_group_label(a,b);
    chosen_source = choose_group_label_source(a,b,chosen_label);
    a = combine_open_clusters(a,b);
    a.label = chosen_label;
    a.label_source = chosen_source;
    if ~isempty(original_label) && ~isempty(b.label) && ...
            original_label > 0 && b.label > 0 && original_label ~= b.label
        a.label_source = append_label_source(a.label_source, ...
            sprintf('label_conflict_%d_vs_%d', original_label, b.label));
    end
    a.member_cluster_ids = unique([a.member_cluster_ids(:); b.member_cluster_ids(:)])';
    a.open = a.open || b.open;
    a.valid_stance = a.valid_stance || b.valid_stance;
    if isempty(a.close_frame) || (~isempty(b.close_frame) && b.close_frame > a.close_frame)
        a.close_frame = b.close_frame;
        a.close_time = b.close_time;
    end
    a.label_source = append_label_source(a.label_source, 'pre_refinement_grouped');
    if promoted_noise_fragment && ~isempty(a.label) && a.label > 0
        a.label_source = append_label_source(a.label_source, ...
            'nearby_noise_fragment_promoted_to_paw');
    end
end

function label=choose_group_label(a,b)
    a_has = ~isempty(a.label) && a.label > 0;
    b_has = ~isempty(b.label) && b.label > 0;
    if a_has && ~b_has
        label = a.label;
    elseif b_has && ~a_has
        label = b.label;
    elseif ~a_has && ~b_has
        label = 0;
    elseif a.label == b.label
        label = a.label;
    elseif cluster_label_confidence(b) > cluster_label_confidence(a)
        label = b.label;
    else
        label = a.label;
    end
end

function source=choose_group_label_source(a,b,label)
    if ~isempty(a.label) && a.label == label && ...
            (~isempty(b.label) && b.label == label)
        source = append_label_source(a.label_source, b.label_source);
    elseif ~isempty(a.label) && a.label == label
        source = a.label_source;
    elseif ~isempty(b.label) && b.label == label
        source = b.label_source;
    else
        source = 'unassigned';
    end
end

function score=cluster_label_confidence(c)
    if isempty(c.label) || c.label <= 0
        score = -Inf;
        return;
    end
    source = string(c.label_source);
    score = c.n_obs;
    if contains(source, "hind_heuristic")
        score = score + 80;
    end
    if contains(source, "lr_rank_pair")
        score = score + 60;
    end
    if contains(source, "IC")
        score = score + 30;
    end
    if contains(source, "integrated_quadrant_vote")
        score = score - 25;
    end
    if contains(source, "spatial_override")
        score = score - 15;
    end
end

function clusters=force_assign_grouped_clusters(clusters,max_dist_px)
    if isempty(clusters)
        return;
    end
    for i = 1:numel(clusters)
        if ~isempty(clusters(i).label) && clusters(i).label > 0
            continue;
        end
        % Preserve clusters already rejected by a concrete noise rule.
        % They are a valid classification, not candidates to force into a paw.
        if is_explicit_noise_cluster(clusters(i))
            clusters(i).label = 0;
            clusters(i).label_source = append_label_source( ...
                clusters(i).label_source, 'final_noise_preserved');
            clusters(i).ic_label_done = true;
            continue;
        end
        [label,source] = fallback_label_for_cluster(clusters,i,max_dist_px);
        clusters(i).label = label;
        clusters(i).label_source = append_label_source(clusters(i).label_source, ...
            source);
        clusters(i).ic_label_done = true;
    end
end

function [label,source]=fallback_label_for_cluster(clusters,idx,max_dist_px)
    label = 0;
    source = 'final_forced_unresolved';
    best_score = Inf;
    for j = 1:numel(clusters)
        if j == idx || isempty(clusters(j).label) || clusters(j).label <= 0
            continue;
        end
        dist = hypot(clusters(idx).display_cx - clusters(j).display_cx, ...
            clusters(idx).display_cy - clusters(j).display_cy);
        gap = cluster_time_gap(clusters(idx), clusters(j));
        if dist > max_dist_px && gap > 1.0
            continue;
        end
        score = dist + 20 * gap - 0.01 * max(0, clusters(j).n_obs);
        if score < best_score
            best_score = score;
            label = clusters(j).label;
            source = 'final_forced_nearest_label';
        end
    end
    if label > 0
        return;
    end

    labeled = find(arrayfun(@(c)~isempty(c.label) && c.label > 0, clusters));
    if ~isempty(labeled)
        [~, best_local] = max([clusters(labeled).n_obs]);
        label = clusters(labeled(best_local)).label;
        source = 'final_forced_global_fallback';
    else
        % No paw identity can be inferred without a labeled reference.
        % Call this noise rather than silently inventing an FL footprint.
        label = 0;
        source = 'final_unresolved_noise';
    end
end

function tf=is_explicit_noise_cluster(cluster)
    source = lower(string(cluster.label_source));
    tf = contains(source, "noise") || contains(source, "duplicate_cluster_merged");
end

function clusters=update_rejected_noise_clusters(clusters,props,frame_idx,t, ...
        pressure_img,link_dist_px,max_drift_px,gap_frames)
%UPDATE_REJECTED_NOISE_CLUSTERS Track rejected pressure components cheaply.
% These never participate in paw-label inference, but retain their timing,
% location, and dynamics for audit/display as an explicit noise class.
    for ci = 1:numel(clusters)
        if clusters(ci).open && (frame_idx - clusters(ci).last_frame) > gap_frames
            clusters(ci) = close_noise_cluster(clusters(ci), frame_idx, t);
        end
    end
    matched = false(1, numel(props));
    for pi = 1:numel(props)
        bcx = props(pi).Centroid(1);
        bcy = props(pi).Centroid(2);
        best_ci = 0;
        best_dist = link_dist_px + 1;
        for ci = 1:numel(clusters)
            if ~clusters(ci).open || (frame_idx - clusters(ci).last_frame) > gap_frames
                continue;
            end
            drift = hypot(clusters(ci).start_cx - bcx, clusters(ci).start_cy - bcy);
            if drift > max_drift_px
                continue;
            end
            dist = hypot(clusters(ci).cx - bcx, clusters(ci).cy - bcy);
            if dist < best_dist
                best_ci = ci;
                best_dist = dist;
            end
        end
        dyn = make_blob_dynamics(frame_idx, t, props(pi), pressure_img);
        if best_ci > 0
            clusters(best_ci).cx = bcx;
            clusters(best_ci).cy = bcy;
            clusters(best_ci).cx_sum = clusters(best_ci).cx_sum + bcx;
            clusters(best_ci).cy_sum = clusters(best_ci).cy_sum + bcy;
            clusters(best_ci).n_obs = clusters(best_ci).n_obs + 1;
            clusters(best_ci).last_frame = frame_idx;
            clusters(best_ci).last_time = t;
            clusters(best_ci).dynamics = append_dynamics(clusters(best_ci).dynamics, dyn);
        else
            ci = numel(clusters) + 1;
            clusters(ci) = make_noise_cluster(bcx, bcy, frame_idx, t, dyn);
        end
        matched(pi) = true;
    end
end

function cluster=make_noise_cluster(cx,cy,frame_idx,t,dyn)
    cluster = struct('cx',cx,'cy',cy,'cx_sum',cx,'cy_sum',cy,'n_obs',1, ...
        'start_frame',frame_idx,'start_time',t,'last_frame',frame_idx, ...
        'last_time',t,'start_cx',cx,'start_cy',cy,'open',true,'label',0, ...
        'label_source','candidate_rejected_noise','ic_label_done',true, ...
        'quad_votes',zeros(1,4),'close_frame',[],'close_time',[], ...
        'valid_stance',false,'dynamics',append_dynamics(empty_dynamics(), dyn), ...
        'display_cx',cx,'display_cy',cy);
end

function clusters=close_open_noise_clusters(clusters,frame_idx,t)
    for ci = 1:numel(clusters)
        if clusters(ci).open
            clusters(ci) = close_noise_cluster(clusters(ci), frame_idx, t);
        end
    end
end

function cluster=close_noise_cluster(cluster,frame_idx,t)
    cluster.open = false;
    cluster.close_frame = frame_idx;
    cluster.close_time = t;
    cluster.valid_stance = false;
    cluster.display_cx = cluster.cx_sum / max(1, cluster.n_obs);
    cluster.display_cy = cluster.cy_sum / max(1, cluster.n_obs);
    cluster.label = 0;
    cluster.label_source = append_label_source(cluster.label_source, 'noise_closed');
    cluster.ic_label_done = true;
end

function clusters=finalize_export_cluster_labels(clusters)
%FINALIZE_EXPORT_CLUSTER_LABELS Guarantee an exhaustive, closed label set.
% Every exported pressure cluster is either one paw (1:4) or noise (0).
    for i = 1:numel(clusters)
        label = clusters(i).label;
        is_paw = ~isempty(label) && isscalar(label) && isfinite(label) && ...
            any(label == 1:4);
        is_noise = ~isempty(label) && isscalar(label) && isfinite(label) && ...
            label == 0;
        if ~is_paw && ~is_noise
            clusters(i).label = 0;
            clusters(i).label_source = append_label_source( ...
                clusters(i).label_source, 'final_unresolved_noise');
        elseif is_noise && ~contains(lower(string(clusters(i).label_source)), "noise")
            clusters(i).label_source = append_label_source( ...
                clusters(i).label_source, 'final_noise');
        end
        clusters(i).ic_label_done = true;
    end
end

function clusters=mark_remote_weak_export_outliers(clusters)
%MARK_REMOTE_WEAK_EXPORT_OUTLIERS Reject late-assigned isolated artifacts.
% The raw tracking pass can only veto labels known while a cluster is open.
% Some small artifacts receive an integrated/fallback paw label after close;
% this final pass applies the same conservative physical criterion to them.
    remote_outlier_dist_px = 60;
    weak_max_obs = 8;
    weak_max_area_px = 24;
    strong_min_obs = 12;
    strong_min_area_px = 25;

    for i = 1:numel(clusters)
        c = clusters(i);
        if isempty(c.label) || c.label <= 0
            continue;
        end
        source = lower(string(c.label_source));
        if contains(source, "body_mask_footprint") || ...
                c.n_obs > weak_max_obs || ...
                current_cluster_max_area(c) > weak_max_area_px
            continue;
        end

        has_remote_strong_overlap = false;
        for j = 1:numel(clusters)
            if j == i || isempty(clusters(j).label) || clusters(j).label <= 0
                continue;
            end
            other = clusters(j);
            if other.n_obs < strong_min_obs || ...
                    current_cluster_max_area(other) < strong_min_area_px || ...
                    cluster_time_gap(c, other) > 0
                continue;
            end
            if hypot(c.display_cx - other.display_cx, ...
                    c.display_cy - other.display_cy) >= remote_outlier_dist_px
                has_remote_strong_overlap = true;
                break;
            end
        end
        if has_remote_strong_overlap
            clusters(i).label = 0;
            clusters(i).label_source = append_label_source( ...
                clusters(i).label_source, 'remote_weak_outlier_noise');
            clusters(i).ic_label_done = true;
            clusters(i).valid_stance = false;
        end
    end
end

function clusters=enforce_overlapping_export_label_uniqueness(clusters)
%ENFORCE_OVERLAPPING_EXPORT_LABEL_UNIQUENESS One simultaneous contact/paw.
% This is intentionally applied after grouping.  Earlier label heuristics
% can legitimately create provisional duplicates, but exported final labels
% must never show two FL/FR/HL/HR contacts at one instant.  Reassign a
% duplicate from its accumulated body-mask quadrant votes before calling it
% noise; a duplicate label is often an identity conflict, not an artifact.
    for label_id = 1:4
        while true
            same_label = find(arrayfun(@(c)~isempty(c.label) && ...
                c.label == label_id, clusters));
            duplicate_pair = [];
            for ai = 1:numel(same_label)
                for bi = ai+1:numel(same_label)
                    if cluster_time_gap(clusters(same_label(ai)), ...
                            clusters(same_label(bi))) == 0
                        duplicate_pair = [same_label(ai), same_label(bi)]; %#ok<AGROW>
                        break;
                    end
                end
                if ~isempty(duplicate_pair)
                    break;
                end
            end
            if isempty(duplicate_pair)
                break;
            end

            score_a = export_label_confidence(clusters(duplicate_pair(1)));
            score_b = export_label_confidence(clusters(duplicate_pair(2)));
            if score_a >= score_b
                drop = duplicate_pair(2);
            else
                drop = duplicate_pair(1);
            end
            replacement = best_unused_quadrant_label(clusters, drop);
            if replacement > 0
                clusters(drop).label = replacement;
                clusters(drop).label_source = append_label_source( ...
                    clusters(drop).label_source, ...
                    'overlapping_duplicate_reassigned_by_quadrant');
            else
                clusters(drop).label = 0;
                clusters(drop).label_source = append_label_source( ...
                    clusters(drop).label_source, ...
                    'overlapping_duplicate_paw_label_noise');
            end
            clusters(drop).ic_label_done = true;
            if replacement == 0
                clusters(drop).valid_stance = false;
            end
        end
    end
end

function label=best_unused_quadrant_label(clusters,idx)
%BEST_UNUSED_QUADRANT_LABEL Use spatial overlap to resolve duplicate paws.
    occupied = false(1,4);
    for j = 1:numel(clusters)
        if j == idx || isempty(clusters(j).label) || clusters(j).label <= 0
            continue;
        end
        if cluster_time_gap(clusters(idx), clusters(j)) == 0
            occupied(clusters(j).label) = true;
        end
    end
    candidates = find(~occupied);
    label = 0;
    if isempty(candidates)
        return;
    end
    votes = clusters(idx).quad_votes;
    if isempty(votes)
        return;
    end
    votes = double(votes(:)');
    votes(end+1:4) = 0;
    [best_vote, local_idx] = max(votes(candidates));
    if best_vote > 0
        label = candidates(local_idx);
    end
end

function score=export_label_confidence(cluster)
% Prefer a direct mask observation and sustained/large pressure support.
    score = double(cluster.n_obs) + 0.1 * current_cluster_max_area(cluster);
    source = lower(string(cluster.label_source));
    if contains(source, "body_mask_footprint")
        score = score + 50;
    end
    if contains(source, "integrated_quadrant_vote")
        score = score - 25;
    end
    if contains(source, "label_conflict") || contains(source, "final_forced")
        score = score - 40;
    end
end

function gap=cluster_time_gap(a,b)
    a_end = cluster_end_time_for_export(a);
    b_end = cluster_end_time_for_export(b);
    if any(isnan([a.start_time, a_end, b.start_time, b_end]))
        gap = Inf;
    else
        gap = max(0, max(a.start_time, b.start_time) - min(a_end, b_end));
    end
end

function tf=is_tailbase_candidate(centroid,tail_x,tail_y,body_cx,body_cy, ...
        head_ax_x,head_ax_y,body_half_len,reject_radius_px,reject_behind_frac, ...
        reject_midline_px)
    tf = false;
    if any(isnan([centroid(:); tail_x; tail_y; body_cx; body_cy; ...
            head_ax_x; head_ax_y; body_half_len]))
        return;
    end

    dist_to_tail = hypot(centroid(1)-tail_x, centroid(2)-tail_y);
    fb = (centroid(1)-body_cx)*head_ax_x + (centroid(2)-body_cy)*head_ax_y;
    right_ax_x = -head_ax_y;
    right_ax_y = head_ax_x;
    lateral = abs((centroid(1)-body_cx)*right_ax_x + ...
        (centroid(2)-body_cy)*right_ax_y);
    behind_body_midline = fb < -reject_behind_frac * body_half_len && ...
        lateral <= reject_midline_px;

    if dist_to_tail <= reject_radius_px || behind_body_midline
        tf = true;
    end
end

function tf=label_is_open_elsewhere(clusters,this_idx,label_id,~,~)
    tf = false;
    if isempty(label_id) || label_id == 0
        return;
    end
    for k = 1:numel(clusters)
        if k == this_idx || ~clusters(k).open
            continue;
        end
        other_label = clusters(k).label;
        if ~isempty(other_label) && other_label == label_id
            tf = true;
            return;
        end
    end
end

function tf=same_girdle_pair_is_plausible(clusters,this_idx,label_id, ...
        body_cx,body_cy,head_ax_x,head_ax_y,max_fb_sep_px)
    tf = true;
    if isempty(label_id) || label_id == 0 || ...
            any(isnan([body_cx; body_cy; head_ax_x; head_ax_y]))
        return;
    end
    pair_id = opposite_same_girdle_label(label_id);
    if pair_id == 0
        return;
    end

    this_fb = (clusters(this_idx).cx - body_cx) * head_ax_x + ...
        (clusters(this_idx).cy - body_cy) * head_ax_y;
    for k = 1:numel(clusters)
        if k == this_idx || ~clusters(k).open
            continue;
        end
        other_label = clusters(k).label;
        if isempty(other_label) || other_label ~= pair_id
            continue;
        end
        other_fb = (clusters(k).cx - body_cx) * head_ax_x + ...
            (clusters(k).cy - body_cy) * head_ax_y;
        if abs(this_fb - other_fb) > max_fb_sep_px
            tf = false;
            return;
        end
    end
end

function label_id=position_label_from_body_axis(x,y,body_cx,body_cy, ...
        head_ax_x,head_ax_y,right_ax_x,right_ax_y,fb_offset)
    label_id = 0;
    if any(isnan([x; y; body_cx; body_cy; head_ax_x; head_ax_y; ...
            right_ax_x; right_ax_y; fb_offset]))
        return;
    end
    fb = (x - body_cx) * head_ax_x + (y - body_cy) * head_ax_y - fb_offset;
    lr = (x - body_cx) * right_ax_x + (y - body_cy) * right_ax_y;
    is_front = fb >= 0;
    is_left = lr < 0;
    label_id = 1 + 2 * double(~is_front) + double(~is_left);
end

function clusters=reorder_open_same_girdle_pairs(clusters,body_cx,body_cy, ...
        head_ax_x,head_ax_y,right_ax_x,right_ax_y,max_fb_sep_px,flip_fore)
    clusters = reorder_open_girdle_pair(clusters, 1, 2, body_cx, body_cy, ...
        head_ax_x, head_ax_y, right_ax_x, right_ax_y, max_fb_sep_px, flip_fore);
    clusters = reorder_open_girdle_pair(clusters, 3, 4, body_cx, body_cy, ...
        head_ax_x, head_ax_y, right_ax_x, right_ax_y, max_fb_sep_px, false);
end

function clusters=resolve_open_duplicate_same_girdle_labels(clusters, ...
        body_cx,body_cy,right_ax_x,right_ax_y)
    clusters = resolve_one_duplicate_girdle_label(clusters, 1, 2, body_cx, ...
        body_cy, right_ax_x, right_ax_y, false);
    clusters = resolve_one_duplicate_girdle_label(clusters, 3, 4, body_cx, ...
        body_cy, right_ax_x, right_ax_y, false);
end

function clusters=resolve_one_duplicate_girdle_label(clusters,left_label, ...
        right_label,body_cx,body_cy,right_ax_x,right_ax_y,reverse_order)
    open_ci = find(arrayfun(@(c)c.open && ~is_explicit_noise_cluster(c), clusters));
    if numel(open_ci) < 2
        return;
    end

    labels = arrayfun(@(c)label_or_zero(c), clusters(open_ci));
    pair_mask = labels == left_label | labels == right_label;
    pair_ci = open_ci(pair_mask);
    pair_labels = labels(pair_mask);
    if numel(pair_ci) < 2
        return;
    end

    duplicate_left = sum(pair_labels == left_label) >= 2 && ...
        ~any(pair_labels == right_label);
    duplicate_right = sum(pair_labels == right_label) >= 2 && ...
        ~any(pair_labels == left_label);
    if ~(duplicate_left || duplicate_right)
        return;
    end

    lr = nan(size(pair_ci));
    for ii = 1:numel(pair_ci)
        ci = pair_ci(ii);
        lr(ii) = (clusters(ci).cx - body_cx) * right_ax_x + ...
            (clusters(ci).cy - body_cy) * right_ax_y;
    end

    [~, order] = sort(lr, 'ascend');
    screen_left_ci = pair_ci(order(1));
    screen_right_ci = pair_ci(order(end));
    if reverse_order
        left_ci = screen_right_ci;
        right_ci = screen_left_ci;
    else
        left_ci = screen_left_ci;
        right_ci = screen_right_ci;
    end

    clusters(left_ci).label = left_label;
    clusters(left_ci).label_source = append_label_source( ...
        clusters(left_ci).label_source, 'duplicate_girdle_lr_fix');
    clusters(left_ci).ic_label_done = true;
    clusters(right_ci).label = right_label;
    clusters(right_ci).label_source = append_label_source( ...
        clusters(right_ci).label_source, 'duplicate_girdle_lr_fix');
    clusters(right_ci).ic_label_done = true;
end

function clusters=assign_open_unlabeled_local_pairs(clusters,body_cx,body_cy, ...
        head_ax_x,head_ax_y,right_ax_x,right_ax_y,fb_offset,max_fb_sep_px)
    clusters = assign_one_unlabeled_local_pair(clusters, 1, 2, body_cx, body_cy, ...
        head_ax_x, head_ax_y, right_ax_x, right_ax_y, fb_offset, ...
        max_fb_sep_px, false);
    clusters = assign_one_unlabeled_local_pair(clusters, 3, 4, body_cx, body_cy, ...
        head_ax_x, head_ax_y, right_ax_x, right_ax_y, fb_offset, ...
        max_fb_sep_px, false);
end

function clusters=assign_one_unlabeled_local_pair(clusters,left_label,right_label, ...
        body_cx,body_cy,head_ax_x,head_ax_y,right_ax_x,right_ax_y,fb_offset, ...
        max_fb_sep_px,reverse_order)
    open_ci = find(arrayfun(@(c)c.open && ~is_explicit_noise_cluster(c), clusters));
    if numel(open_ci) < 2
        return;
    end

    fb = nan(size(open_ci));
    lr = nan(size(open_ci));
    for ii = 1:numel(open_ci)
        ci = open_ci(ii);
        fb(ii) = (clusters(ci).cx - body_cx) * head_ax_x + ...
            (clusters(ci).cy - body_cy) * head_ax_y - fb_offset;
        lr(ii) = (clusters(ci).cx - body_cx) * right_ax_x + ...
            (clusters(ci).cy - body_cy) * right_ax_y;
    end

    is_front_girdle = left_label <= 2;
    if is_front_girdle
        girdle_ci = open_ci(fb >= 0);
        girdle_fb = fb(fb >= 0);
        girdle_lr = lr(fb >= 0);
    else
        girdle_ci = open_ci(fb < 0);
        girdle_fb = fb(fb < 0);
        girdle_lr = lr(fb < 0);
    end
    if numel(girdle_ci) < 2
        return;
    end

    labels = arrayfun(@(c)label_or_zero(c), clusters(girdle_ci));
    pair_mask = labels == 0 | labels == left_label | labels == right_label;
    girdle_ci = girdle_ci(pair_mask);
    girdle_fb = girdle_fb(pair_mask);
    girdle_lr = girdle_lr(pair_mask);
    labels = labels(pair_mask);
    if numel(girdle_ci) < 2 || ~any(labels == 0)
        return;
    end

    best_pair = [0 0];
    best_score = -Inf;
    for ia = 1:numel(girdle_ci)
        for ib = ia+1:numel(girdle_ci)
            pair_labels = labels([ia ib]);
            if ~any(pair_labels == 0)
                continue;
            end
            fb_sep = abs(girdle_fb(ia) - girdle_fb(ib));
            if fb_sep > max_fb_sep_px
                continue;
            end
            lr_sep = abs(girdle_lr(ia) - girdle_lr(ib));
            score = lr_sep + clusters(girdle_ci(ia)).n_obs + ...
                clusters(girdle_ci(ib)).n_obs - fb_sep;
            if score > best_score
                best_score = score;
                best_pair = [ia ib];
            end
        end
    end
    if best_pair(1) == 0
        return;
    end

    pair_ci = girdle_ci(best_pair);
    pair_lr = girdle_lr(best_pair);
    [~, order] = sort(pair_lr, 'ascend');
    screen_left_ci = pair_ci(order(1));
    screen_right_ci = pair_ci(order(end));
    if reverse_order
        left_ci = screen_right_ci;
        right_ci = screen_left_ci;
    else
        left_ci = screen_left_ci;
        right_ci = screen_right_ci;
    end

    clusters(left_ci).label = left_label;
    clusters(left_ci).label_source = append_label_source( ...
        clusters(left_ci).label_source, 'local_frame_pair_assign');
    clusters(left_ci).ic_label_done = true;
    clusters(right_ci).label = right_label;
    clusters(right_ci).label_source = append_label_source( ...
        clusters(right_ci).label_source, 'local_frame_pair_assign');
    clusters(right_ci).ic_label_done = true;
end

function clusters=mark_open_isolated_noise_clusters(clusters)
    open_ci = find(arrayfun(@(c)c.open && ~is_explicit_noise_cluster(c), clusters));
    if numel(open_ci) < 2
        return;
    end
    xy = [[clusters(open_ci).cx]' [clusters(open_ci).cy]'];
    % A small, short-lived label far from a strong simultaneous contact is
    % physically implausible and is marked as noise, even when a fallback
    % geometry rule has assigned it a paw label. Direct projected-body-mask
    % contacts are preserved; the body mask is stronger evidence than this
    % spatial outlier heuristic.
    remote_outlier_dist_px = 60;
    weak_max_obs = 8;
    weak_max_area_px = 24;
    strong_min_obs = 12;
    strong_min_area_px = 25;
    for ii = 1:numel(open_ci)
        ci = open_ci(ii);
        others = setdiff(1:numel(open_ci), ii);
        nearest = min(hypot(xy(others,1) - xy(ii,1), xy(others,2) - xy(ii,2)));
        area = current_cluster_area(clusters(ci));

        source = lower(string(clusters(ci).label_source));
        is_direct_mask_contact = contains(source, "body_mask_footprint");
        is_weak = clusters(ci).n_obs <= weak_max_obs && ...
            current_cluster_max_area(clusters(ci)) <= weak_max_area_px;
        strong_other = false(size(others));
        for oi = 1:numel(others)
            other = clusters(open_ci(others(oi)));
            strong_other(oi) = other.n_obs >= strong_min_obs && ...
                current_cluster_max_area(other) >= strong_min_area_px;
        end
        if is_weak && ~is_direct_mask_contact && any(strong_other)
            strong_dist = min(hypot(xy(others(strong_other),1) - xy(ii,1), ...
                xy(others(strong_other),2) - xy(ii,2)));
            if strong_dist >= remote_outlier_dist_px
                clusters(ci).label = 0;
                clusters(ci).label_source = append_label_source( ...
                    clusters(ci).label_source, 'remote_weak_outlier_noise');
                clusters(ci).ic_label_done = true;
                continue;
            end
        end

        if ~isempty(clusters(ci).label) && clusters(ci).label > 0
            continue;
        end
        if clusters(ci).n_obs > 1
            continue;
        end
        if nearest >= 45 && area <= 4
            clusters(ci).label = 0;
            clusters(ci).label_source = append_label_source( ...
                clusters(ci).label_source, 'isolated_noise');
            clusters(ci).ic_label_done = true;
        end
    end
end

function clusters=mark_open_edge_artifact_noise_clusters(clusters,img_w,img_h)
    edge_margin_px = 2;
    max_edge_area_px = 4;
    for ci = 1:numel(clusters)
        if ~clusters(ci).open
            continue;
        end
        if ~cluster_touches_outer_edge(clusters(ci), img_w, img_h, edge_margin_px)
            continue;
        end
        if current_cluster_max_area(clusters(ci)) > max_edge_area_px
            continue;
        end
        clusters(ci).label = 0;
        clusters(ci).label_source = append_label_source( ...
            clusters(ci).label_source, 'outer_edge_artifact_noise');
        clusters(ci).ic_label_done = true;
    end
end

function tf=cluster_touches_outer_edge(cluster,img_w,img_h,margin_px)
    tf = false;
    if ~isfield(cluster, 'dynamics') || isempty(cluster.dynamics.bbox_x)
        return;
    end
    x1 = min(cluster.dynamics.bbox_x, [], 'omitnan');
    y1 = min(cluster.dynamics.bbox_y, [], 'omitnan');
    x2 = max(cluster.dynamics.bbox_x + cluster.dynamics.bbox_w - 1, [], ...
        'omitnan');
    y2 = max(cluster.dynamics.bbox_y + cluster.dynamics.bbox_h - 1, [], ...
        'omitnan');
    if any(isnan([x1, y1, x2, y2]))
        return;
    end
    tf = x1 <= margin_px || y1 <= margin_px || ...
        x2 >= (img_w - margin_px + 1) || y2 >= (img_h - margin_px + 1);
end

function clusters=resolve_open_labels_by_elimination(clusters)
    open_ci = find(arrayfun(@(c)c.open && ~is_explicit_noise_cluster(c), clusters));
    if numel(open_ci) < 4
        return;
    end

    keep = true(size(open_ci));
    for ii = 1:numel(open_ci)
        keep(ii) = ~is_explicit_noise_cluster(clusters(open_ci(ii)));
    end
    open_ci = open_ci(keep);
    if numel(open_ci) < 4
        return;
    end

    labels = arrayfun(@(c)label_or_zero(c), clusters(open_ci));
    positive = labels > 0 & labels <= 4;
    if sum(positive) < 4
        return;
    end

    counts = arrayfun(@(lbl)sum(labels == lbl), 1:4);
    missing = find(counts == 0);
    duplicate_labels = find(counts > 1);
    if numel(missing) ~= 1 || isempty(duplicate_labels)
        return;
    end

    best_ci = 0;
    best_score = Inf;
    for lbl = duplicate_labels
        dup_ci = open_ci(labels == lbl);
        for kk = 1:numel(dup_ci)
            ci = dup_ci(kk);
            score = open_label_confidence_for_elimination(clusters(ci));
            if score < best_score
                best_score = score;
                best_ci = ci;
            end
        end
    end

    if best_ci == 0
        return;
    end
    clusters(best_ci).label = missing(1);
    clusters(best_ci).label_source = append_label_source( ...
        clusters(best_ci).label_source, 'elimination_missing_label_assign');
    clusters(best_ci).ic_label_done = true;
end

function score=open_label_confidence_for_elimination(cluster)
    score = double(cluster.n_obs);
    source = string(cluster.label_source);
    if contains(source, "hind_heuristic")
        score = score + 80;
    end
    if contains(source, "lr_rank_pair")
        score = score + 70;
    end
    if contains(source, "integrated_quadrant_vote")
        score = score + 60;
    end
    if contains(source, "local_frame_pair_assign")
        score = score - 20;
    end
    if contains(source, "local_frame_noncompetitive_assign")
        score = score - 30;
    end
    if contains(source, "local_frame_forced_occupied_label")
        score = score - 50;
    end
    if contains(source, "safety_orphan")
        score = score - 15;
    end
    if contains(source, "duplicate_girdle_lr_fix")
        score = score - 10;
    end
end

function clusters=mark_open_severe_anatomy_noise_clusters(clusters)
    clusters = mark_one_severe_anatomy_pair(clusters, 1, 2);
    clusters = mark_one_severe_anatomy_pair(clusters, 3, 4);
end

function clusters=mark_one_severe_anatomy_pair(clusters,left_label,right_label)
    left_ci = find_open_label(clusters, left_label);
    right_ci = find_open_label(clusters, right_label);
    if left_ci == 0 || right_ci == 0
        return;
    end

    same_dist = open_cluster_distance(clusters(left_ci), clusters(right_ci));
    min_severe_same_girdle_px = 45;
    if same_dist < min_severe_same_girdle_px
        return;
    end

    other_ci = find(arrayfun(@(c)c.open && ~isempty(c.label) && ...
        c.label > 0 && c.label ~= left_label && c.label ~= right_label && ...
        ~contains(string(c.label_source), "noise"), clusters));
    if isempty(other_ci)
        return;
    end

    left_nearest = nearest_open_cluster_distance(clusters, left_ci, other_ci);
    right_nearest = nearest_open_cluster_distance(clusters, right_ci, other_ci);
    nearest_cross = min(left_nearest, right_nearest);
    if ~isfinite(nearest_cross) || nearest_cross <= 0
        return;
    end

    severe_ratio = 2.4;
    isolated_gap_px = 32;
    drop_ci = 0;
    if same_dist >= severe_ratio * nearest_cross
        if left_nearest >= isolated_gap_px && right_nearest == nearest_cross
            drop_ci = left_ci;
        elseif right_nearest >= isolated_gap_px && left_nearest == nearest_cross
            drop_ci = right_ci;
        end
    end
    if drop_ci == 0
        return;
    end

    clusters(drop_ci).label = 0;
    clusters(drop_ci).label_source = append_label_source( ...
        clusters(drop_ci).label_source, 'severe_anatomy_veto_noise');
    clusters(drop_ci).ic_label_done = true;
end

function d=nearest_open_cluster_distance(clusters,ci,other_ci)
    d = Inf;
    for ii = 1:numel(other_ci)
        d = min(d, open_cluster_distance(clusters(ci), clusters(other_ci(ii))));
    end
end

function d=open_cluster_distance(a,b)
    d = hypot(a.cx - b.cx, a.cy - b.cy);
end

function area=current_cluster_area(cluster)
    area = 0;
    if isfield(cluster, 'dynamics') && isfield(cluster.dynamics, 'area') && ...
            ~isempty(cluster.dynamics.area)
        area = cluster.dynamics.area(end);
    end
end

function area=current_cluster_max_area(cluster)
    area = 0;
    if isfield(cluster, 'dynamics') && isfield(cluster.dynamics, 'area') && ...
            ~isempty(cluster.dynamics.area)
        area = max(cluster.dynamics.area, [], 'omitnan');
        if isnan(area)
            area = 0;
        end
    end
end

function clusters=assign_remaining_open_unlabeled_noncompetitive(clusters, ...
        body_cx,body_cy,head_ax_x,head_ax_y,right_ax_x,right_ax_y,fb_offset)
    for ci = 1:numel(clusters)
        if ~clusters(ci).open
            continue;
        end
        if ~isempty(clusters(ci).label) && clusters(ci).label > 0
            continue;
        end
        if is_explicit_noise_cluster(clusters(ci))
            continue;
        end

        preferred = local_frame_label_from_body_axis(clusters(ci).cx, ...
            clusters(ci).cy, body_cx, body_cy, head_ax_x, head_ax_y, ...
            right_ax_x, right_ax_y, fb_offset);
        if preferred == 0
            preferred = position_label_from_body_axis(clusters(ci).cx, ...
                clusters(ci).cy, body_cx, body_cy, head_ax_x, head_ax_y, ...
                right_ax_x, right_ax_y, fb_offset);
        end
        candidates = local_noncompetitive_label_order(preferred);

        chosen = 0;
        for k = 1:numel(candidates)
            cand = candidates(k);
            if cand == 0
                continue;
            end
            if ~label_is_open_elsewhere(clusters, ci, cand, NaN, NaN)
                chosen = cand;
                break;
            end
        end
        if chosen == 0 && preferred > 0
            chosen = preferred;
        end
        if chosen == 0
            chosen = first_available_label(clusters, ci);
        end

        if chosen > 0
            clusters(ci).label = chosen;
            if label_is_open_elsewhere(clusters, ci, chosen, NaN, NaN)
                clusters(ci).label_source = append_label_source( ...
                    clusters(ci).label_source, ...
                    'local_frame_forced_occupied_label');
            else
                clusters(ci).label_source = append_label_source( ...
                    clusters(ci).label_source, ...
                    'local_frame_noncompetitive_assign');
            end
            clusters(ci).ic_label_done = true;
        end
    end
end

function label_id=local_frame_label_from_body_axis(x,y,body_cx,body_cy, ...
        head_ax_x,head_ax_y,right_ax_x,right_ax_y,fb_offset)
    label_id = 0;
    if any(isnan([x; y; body_cx; body_cy; head_ax_x; head_ax_y; ...
            right_ax_x; right_ax_y; fb_offset]))
        return;
    end
    fb = (x - body_cx) * head_ax_x + (y - body_cy) * head_ax_y - fb_offset;
    lr = (x - body_cx) * right_ax_x + (y - body_cy) * right_ax_y;
    if fb >= 0
        % The body-axis convention is identical for fore- and hindlimbs:
        % negative lateral coordinate is the animal's left side.
        if lr < 0
            label_id = 1; % FL
        else
            label_id = 2; % FR
        end
    else
        if lr < 0
            label_id = 3; % HL
        else
            label_id = 4; % HR
        end
    end
end

function candidates=local_noncompetitive_label_order(preferred)
    if preferred == 0
        candidates = 1:4;
        return;
    end
    pair = opposite_same_girdle_label(preferred);
    if preferred <= 2
        same_girdle = [1 2];
        other_girdle = [3 4];
    else
        same_girdle = [3 4];
        other_girdle = [1 2];
    end
    candidates = unique([preferred, pair, same_girdle, other_girdle], 'stable');
end

function label=first_available_label(clusters,this_idx)
    label = 0;
    for cand = 1:4
        if ~label_is_open_elsewhere(clusters, this_idx, cand, NaN, NaN)
            label = cand;
            return;
        end
    end
end

function label=label_or_zero(cluster)
    if is_explicit_noise_cluster(cluster)
        label = NaN;
    elseif isempty(cluster.label)
        label = 0;
    else
        label = cluster.label;
    end
end

function clusters=assign_open_girdles_by_lateral_rank(clusters,body_cx,body_cy, ...
        head_ax_x,head_ax_y,right_ax_x,right_ax_y,fb_offset,max_fb_sep_px, ...
        flip_fore)
    open_ci = find(arrayfun(@(c)c.open && ~is_explicit_noise_cluster(c), clusters));
    if numel(open_ci) < 2
        return;
    end

    fb = nan(size(open_ci));
    lr = nan(size(open_ci));
    for ii = 1:numel(open_ci)
        ci = open_ci(ii);
        fb(ii) = (clusters(ci).cx - body_cx) * head_ax_x + ...
            (clusters(ci).cy - body_cy) * head_ax_y - fb_offset;
        lr(ii) = (clusters(ci).cx - body_cx) * right_ax_x + ...
            (clusters(ci).cy - body_cy) * right_ax_y;
    end

    clusters = assign_one_open_girdle_by_rank(clusters, open_ci(fb >= 0), ...
        fb(fb >= 0), lr(fb >= 0), 1, 2, max_fb_sep_px, flip_fore);
    clusters = assign_one_open_girdle_by_rank(clusters, open_ci(fb < 0), ...
        fb(fb < 0), lr(fb < 0), 3, 4, max_fb_sep_px, false);
end

function clusters=assign_one_open_girdle_by_rank(clusters,candidates,fb_vals,lr_vals, ...
        left_label,right_label,max_fb_sep_px,flip_lateral_labels)
    if numel(candidates) < 2
        return;
    end

    eligible = false(size(candidates));
    for ii = 1:numel(candidates)
        candidate = clusters(candidates(ii));
        lbl = candidate.label;
        eligible(ii) = ~is_explicit_noise_cluster(candidate) && ...
            (isempty(lbl) || lbl == 0 || lbl == left_label || lbl == right_label);
    end
    candidates = candidates(eligible);
    fb_vals = fb_vals(eligible);
    lr_vals = lr_vals(eligible);
    if numel(candidates) < 2
        return;
    end

    best_pair = [0 0];
    best_score = -Inf;
    for ia = 1:numel(candidates)
        for ib = ia+1:numel(candidates)
            fb_sep = abs(fb_vals(ia) - fb_vals(ib));
            if fb_sep > max_fb_sep_px
                continue;
            end
            score = clusters(candidates(ia)).n_obs + clusters(candidates(ib)).n_obs - fb_sep;
            if score > best_score
                best_score = score;
                best_pair = [ia ib];
            end
        end
    end
    if best_pair(1) == 0
        return;
    end

    pair_ci = candidates(best_pair);
    pair_lr = lr_vals(best_pair);
    [~, order] = sort(pair_lr, 'ascend');
    if flip_lateral_labels
        left_ci = pair_ci(order(2));
        right_ci = pair_ci(order(1));
    else
        left_ci = pair_ci(order(1));
        right_ci = pair_ci(order(2));
    end

    clusters(left_ci).label = left_label;
    clusters(left_ci).label_source = append_label_source( ...
        clusters(left_ci).label_source, 'lr_rank_pair');
    clusters(left_ci).ic_label_done = true;
    clusters(right_ci).label = right_label;
    clusters(right_ci).label_source = append_label_source( ...
        clusters(right_ci).label_source, 'lr_rank_pair');
    clusters(right_ci).ic_label_done = true;
end

function source=append_label_source(source,tag)
    if isempty(source)
        source = tag;
    elseif ~contains(source, tag)
        source = [source '+' tag];
    end
end

function clusters=reorder_open_girdle_pair(clusters,left_label,right_label, ...
        body_cx,body_cy,head_ax_x,head_ax_y,right_ax_x,right_ax_y,max_fb_sep_px, ...
        flip_lateral_labels)
    left_ci = find_open_label(clusters, left_label);
    right_ci = find_open_label(clusters, right_label);
    if left_ci == 0 || right_ci == 0
        return;
    end

    fb_left = (clusters(left_ci).cx - body_cx) * head_ax_x + ...
        (clusters(left_ci).cy - body_cy) * head_ax_y;
    fb_right = (clusters(right_ci).cx - body_cx) * head_ax_x + ...
        (clusters(right_ci).cy - body_cy) * head_ax_y;
    if abs(fb_left - fb_right) > max_fb_sep_px
        return;
    end

    lr_left = (clusters(left_ci).cx - body_cx) * right_ax_x + ...
        (clusters(left_ci).cy - body_cy) * right_ax_y;
    lr_right = (clusters(right_ci).cx - body_cx) * right_ax_x + ...
        (clusters(right_ci).cy - body_cy) * right_ax_y;

    is_correct_order = (~flip_lateral_labels && lr_left <= lr_right) || ...
        (flip_lateral_labels && lr_left >= lr_right);
    if is_correct_order
        return;
    end

    clusters(left_ci).label = right_label;
    clusters(left_ci).label_source = [clusters(left_ci).label_source '+lr_rank_swap'];
    clusters(right_ci).label = left_label;
    clusters(right_ci).label_source = [clusters(right_ci).label_source '+lr_rank_swap'];
end

function ci=find_open_label(clusters,label_id)
    ci = 0;
    best_n = -Inf;
    for k = 1:numel(clusters)
        if ~clusters(k).open || isempty(clusters(k).label) || clusters(k).label ~= label_id
            continue;
        end
        if clusters(k).n_obs > best_n
            ci = k;
            best_n = clusters(k).n_obs;
        end
    end
end

function pair_id=opposite_same_girdle_label(label_id)
    switch label_id
        case 1, pair_id = 2; % FL -> FR
        case 2, pair_id = 1; % FR -> FL
        case 3, pair_id = 4; % HL -> HR
        case 4, pair_id = 3; % HR -> HL
        otherwise, pair_id = 0;
    end
end

function tf=cluster_is_valid_stance(cluster,min_stance_sec)
    tf = false;
    if isempty(cluster.start_time)
        return;
    end
    if ~isempty(cluster.close_time)
        tf = (cluster.close_time - cluster.start_time) >= min_stance_sec;
    elseif ~isempty(cluster.last_time)
        tf = (cluster.last_time - cluster.start_time) >= min_stance_sec;
    end
end

function tf=open_cluster_is_valid_candidate(cluster,t,min_stance_sec)
    tf = false;
    if isempty(cluster.start_time)
        return;
    end
    tf = (t - cluster.start_time) >= min_stance_sec;
end

function [label_id,source]=label_from_integrated_votes(quad_votes,min_total_vote)
    label_id = 0;
    source = '';
    if isempty(quad_votes) || sum(quad_votes) < min_total_vote
        return;
    end
    [~, label_id] = max(quad_votes);
    source = 'integrated_quadrant_vote';
end

function dyn=empty_dynamics()
    dyn = struct('frame_idx',[],'time',[],'cx',[],'cy',[],'area',[], ...
        'total_pressure',[],'mean_pressure',[],'max_pressure',[], ...
        'spatial_std',[],'global_total_pressure',[], ...
        'bbox_x',[],'bbox_y',[],'bbox_w',[],'bbox_h',[]);
end

function dyn=make_blob_dynamics(frame_idx,t,prop,pressure_img)
    dyn = empty_dynamics();
    pix = prop.PixelIdxList;
    vals = double(pressure_img(pix));
    [rows, cols] = ind2sub(size(pressure_img), pix);

    dyn.frame_idx = frame_idx;
    dyn.time = t;
    dyn.cx = prop.Centroid(1);
    dyn.cy = prop.Centroid(2);
    dyn.area = prop.Area;
    dyn.total_pressure = sum(vals);
    dyn.mean_pressure = mean(vals);
    dyn.max_pressure = max(vals);
    dyn.global_total_pressure = NaN;
    if dyn.total_pressure > 0
        dx = cols - dyn.cx;
        dy = rows - dyn.cy;
        dyn.spatial_std = sqrt(sum(vals .* (dx.^2 + dy.^2)) / dyn.total_pressure);
    else
        dyn.spatial_std = NaN;
    end
    dyn.bbox_x = min(cols);
    dyn.bbox_y = min(rows);
    dyn.bbox_w = max(cols) - min(cols) + 1;
    dyn.bbox_h = max(rows) - min(rows) + 1;
end

function dyn=append_dynamics(dyn,new_dyn)
    fields = fieldnames(new_dyn);
    for fi = 1:numel(fields)
        f = fields{fi};
        value = new_dyn.(f);
        if isempty(value)
            value = NaN;
        end
        dyn.(f)(end+1,1) = value;
    end
end

function [events, clean_events, params, source]=build_footstep_export( ...
        clusters,label_names,filename,fpath,video_cam1_path,pressure_thresh, ...
        min_contact_area,cluster_dist_px,cluster_gap_frames,swing_min_sec, ...
        tactile_mm_per_px,gait_merge_max_dist_mm,gait_merge_max_dist_px, ...
        gait_min_stance_sec,dynamic_peak_fraction,dynamic_search_max_sec, ...
        dynamic_roi_pad_px,dynamic_roi_max_size_px,dynamic_smooth_frames,dynamic_min_on_frames, ...
        dynamic_off_frames,dynamic_std_growth_factor,dynamic_std_growth_min_px, ...
        dynamic_centroid_drift_max_px, ...
        dynamic_split_valley_fraction,dynamic_split_min_peak_fraction, ...
        dynamic_split_centroid_jump_px,dynamic_global_dropout_fraction, ...
        dynamic_component_min_area_px,dynamic_component_overlap_dilate_px, ...
        dynamic_component_merge_area_factor, ...
        pressure_frames,pressure_times,pressure_frame_indices,camera1_timestamps, ...
        prelabel_merge_dist_px,prelabel_merge_max_area,peak_seed_min_density, ...
        peak_seed_min_mean_pressure,peak_seed_candidate_mode,tac_fps,p_w,p_h)

    events = repmat(empty_footstep_event(), 0, 1);
    for ci = 1:numel(clusters)
        events(ci,1) = cluster_to_footstep_event(clusters(ci), ci, label_names, ...
            pressure_frames, pressure_times, pressure_frame_indices, ...
            dynamic_peak_fraction, dynamic_search_max_sec, dynamic_roi_pad_px, ...
            dynamic_roi_max_size_px, dynamic_smooth_frames, dynamic_min_on_frames, ...
            dynamic_off_frames, dynamic_std_growth_factor, dynamic_std_growth_min_px, ...
            dynamic_centroid_drift_max_px, ...
            dynamic_split_valley_fraction, dynamic_split_min_peak_fraction, ...
            dynamic_split_centroid_jump_px, dynamic_global_dropout_fraction, ...
            dynamic_component_min_area_px, dynamic_component_overlap_dilate_px, ...
            dynamic_component_merge_area_factor, gait_min_stance_sec);
    end

    clean_events = build_clean_gait_events(events, swing_min_sec, ...
        gait_merge_max_dist_px, gait_min_stance_sec);
    [events, clean_events] = mark_clean_event_representatives(events, clean_events);

    params = struct();
    params.pressure_thresh = pressure_thresh;
    params.min_contact_area = min_contact_area;
    params.algorithm_variant = 'peak_seed';
    params.prelabel_merge_dist_px = prelabel_merge_dist_px;
    params.prelabel_merge_max_area = prelabel_merge_max_area;
    params.peak_seed_min_density = peak_seed_min_density;
    params.peak_seed_min_mean_pressure = peak_seed_min_mean_pressure;
    params.peak_seed_candidate_mode = peak_seed_candidate_mode;
    params.seed_strategy = ['High-confidence footprint cores are detected ', ...
        'with stricter area filtering; refined IC/LO are recovered from ', ...
        'component-tracked dynamic ROI pressure.'];
    params.cluster_dist_px = cluster_dist_px;
    params.cluster_gap_frames = cluster_gap_frames;
    params.swing_min_sec = swing_min_sec;
    params.tactile_mm_per_px = tactile_mm_per_px;
    params.gait_merge_max_dist_mm = gait_merge_max_dist_mm;
    params.gait_merge_max_dist_px = gait_merge_max_dist_px;
    params.gait_min_stance_sec = gait_min_stance_sec;
    params.dynamic_peak_fraction = dynamic_peak_fraction;
    params.dynamic_search_max_sec = dynamic_search_max_sec;
    params.dynamic_roi_pad_px = dynamic_roi_pad_px;
    params.dynamic_roi_max_size_px = dynamic_roi_max_size_px;
    params.dynamic_smooth_frames = dynamic_smooth_frames;
    params.dynamic_min_on_frames = dynamic_min_on_frames;
    params.dynamic_off_frames = dynamic_off_frames;
    params.dynamic_std_growth_factor = dynamic_std_growth_factor;
    params.dynamic_std_growth_min_px = dynamic_std_growth_min_px;
    params.dynamic_centroid_drift_max_px = dynamic_centroid_drift_max_px;
    params.dynamic_split_valley_fraction = dynamic_split_valley_fraction;
    params.dynamic_split_min_peak_fraction = dynamic_split_min_peak_fraction;
    params.dynamic_split_centroid_jump_px = dynamic_split_centroid_jump_px;
    params.dynamic_global_dropout_fraction = dynamic_global_dropout_fraction;
    params.dynamic_component_min_area_px = dynamic_component_min_area_px;
    params.dynamic_component_overlap_dilate_px = dynamic_component_overlap_dilate_px;
    params.dynamic_component_merge_area_factor = dynamic_component_merge_area_factor;
    params.tactile_fps = tac_fps;
    params.board_width_px = p_w;
    params.board_height_px = p_h;

    source = struct();
    source.tactile_filename = filename;
    source.tactile_folder = fpath;
    source.video_cam1_path = video_cam1_path;
    source.camera1_frame_timestamps = camera1_timestamps;
    source.export_created = char(datetime('now'));
end

function print_footstep_export_summary(events,clean_events)
    if isempty(events)
        fprintf('Export summary: footstep_events=0, clean_events=0\n');
        return;
    end

    labels = string({events.label});
    footprint = ismember(labels, ["FL", "FR", "HL", "HR"]);
    noise = labels == "noise";
    unresolved = ~(footprint | noise);
    clean_labels = {};
    if ~isempty(clean_events)
        clean_labels = {clean_events.label};
    end

    fprintf(['Export summary: footstep_events=%d, footprints=%d, noise=%d, ', ...
        'unassigned=%d, clean_events=%d\n'], ...
        numel(events), sum(footprint), sum(noise), sum(unresolved), ...
        numel(clean_events));
    fprintf('  Raw grouped events by paw: %s\n', ...
        format_label_counts(cellstr(labels), {'FL','FR','HL','HR','noise'}));
    fprintf('  Clean playback events by paw: %s\n', ...
        format_label_counts(clean_labels, {'FL','FR','HL','HR'}));
end

function s=format_label_counts(labels,wanted_labels)
    if isempty(labels)
        s = 'none';
        return;
    end
    parts = cell(1, numel(wanted_labels));
    for ii = 1:numel(wanted_labels)
        parts{ii} = sprintf('%s=%d', wanted_labels{ii}, ...
            sum(strcmp(labels, wanted_labels{ii})));
    end
    s = strjoin(parts, ', ');
end

function event=empty_footstep_event()
    event = struct('cluster_id',[],'label','','label_id',[],'label_source','', ...
        'member_cluster_ids',[], ...
        'start_time',[],'end_time',[],'duration',[],'detected_start_time',[], ...
        'detected_end_time',[],'refined_start_time',[],'refined_end_time',[], ...
        'start_frame',[],'end_frame',[],'valid_stance',false,'n_obs',[], ...
        'centroid_x',[],'centroid_y',[],'quad_votes',[],'dynamics',empty_dynamics(), ...
        'dynamic_roi',[],'roi_frames',[],'dynamic_peak_total_pressure',[], ...
        'dynamic_threshold_total_pressure',[],'dynamic_start_truncated',false, ...
        'dynamic_end_truncated',false,'clean_status','raw');
end

function event=cluster_to_footstep_event(cluster,cluster_id,label_names, ...
        pressure_frames,pressure_times,pressure_frame_indices,peak_fraction, ...
        search_max_sec,roi_pad_px,roi_max_size_px,smooth_frames,min_on_frames, ...
        off_frames,std_growth_factor,std_growth_min_px,centroid_drift_max_px, ...
        split_valley_fraction,split_min_peak_fraction,split_centroid_jump_px, ...
        global_dropout_fraction,component_min_area_px,component_overlap_dilate_px, ...
        component_merge_area_factor,gait_min_stance_sec)
    event = empty_footstep_event();
    event.cluster_id = cluster_id;
    if isfield(cluster, 'member_cluster_ids')
        event.member_cluster_ids = cluster.member_cluster_ids;
    else
        event.member_cluster_ids = cluster_id;
    end
    event.label_id = cluster.label;
    event.label = label_to_name(cluster.label, label_names);
    event.label_source = cluster.label_source;
    event.detected_start_time = cluster.start_time;
    event.detected_end_time = cluster_end_time_for_export(cluster);
    event.start_time = event.detected_start_time;
    event.end_time = event.detected_end_time;
    event.duration = event.end_time - event.start_time;
    event.start_frame = cluster.start_frame;
    event.end_frame = cluster.last_frame;
    if ~isempty(cluster.close_frame)
        event.end_frame = cluster.close_frame;
    end
    event.valid_stance = cluster.valid_stance;
    event.n_obs = cluster.n_obs;
    event.centroid_x = cluster.display_cx;
    event.centroid_y = cluster.display_cy;
    event.quad_votes = cluster.quad_votes;
    event.dynamics = cluster.dynamics;
    if ~isempty(cluster.dynamics.time)
        [event.dynamics, event.dynamic_roi, event.roi_frames, ...
            event.dynamic_peak_total_pressure, event.dynamic_threshold_total_pressure, ...
            refined_start, refined_end, event.dynamic_start_truncated, ...
            event.dynamic_end_truncated] = ...
            refine_dynamics_from_raw_pressure(cluster, pressure_frames, ...
            pressure_times, pressure_frame_indices, peak_fraction, ...
            search_max_sec, roi_pad_px, roi_max_size_px, smooth_frames, ...
            min_on_frames, off_frames, std_growth_factor, std_growth_min_px, ...
            centroid_drift_max_px, split_valley_fraction, split_min_peak_fraction, ...
            split_centroid_jump_px, global_dropout_fraction, component_min_area_px, ...
            component_overlap_dilate_px, component_merge_area_factor);
        if ~isnan(refined_start) && ~isnan(refined_end)
            event.refined_start_time = refined_start;
            event.refined_end_time = refined_end;
            event.start_time = refined_start;
            event.end_time = refined_end;
            event.duration = event.end_time - event.start_time;
            event.valid_stance = event.duration >= gait_min_stance_sec && ...
                ~event.dynamic_start_truncated && ~event.dynamic_end_truncated;
        end
    end
end

function name=label_to_name(label_id,label_names)
    if isempty(label_id) || label_id == 0
        name = 'noise';
    elseif label_id >= 1 && label_id <= numel(label_names)
        name = label_names{label_id};
    else
        name = 'noise';
    end
end

function t=cluster_end_time_for_export(cluster)
    if ~isempty(cluster.close_time)
        t = cluster.close_time;
    elseif ~isempty(cluster.last_time)
        t = cluster.last_time;
    else
        t = NaN;
    end
end

function [dyn,roi,roi_frames,peak_total,threshold_total,refined_start,refined_end, ...
        start_truncated,end_truncated]= ...
        refine_dynamics_from_raw_pressure(cluster,pressure_frames,pressure_times, ...
        pressure_frame_indices,peak_fraction,search_max_sec,roi_pad_px, ...
        roi_max_size_px,smooth_frames,min_on_frames,off_frames, ...
        std_growth_factor,std_growth_min_px,centroid_drift_max_px, ...
        split_valley_fraction,split_min_peak_fraction,split_centroid_jump_px, ...
        global_dropout_fraction,component_min_area_px,component_overlap_dilate_px, ...
        component_merge_area_factor)

    dyn = empty_dynamics();
    roi = struct('x1',NaN,'x2',NaN,'y1',NaN,'y2',NaN);
    roi_frames = [];
    peak_total = NaN;
    threshold_total = NaN;
    refined_start = NaN;
    refined_end = NaN;
    start_truncated = false;
    end_truncated = false;

    detected_start = cluster.start_time;
    detected_end = cluster_end_time_for_export(cluster);
    if isempty(detected_start) || isnan(detected_start) || isnan(detected_end)
        return;
    end

    [x1,x2,y1,y2] = cluster_dynamic_roi(cluster, size(pressure_frames), ...
        roi_pad_px, roi_max_size_px);
    if isnan(x1)
        return;
    end
    roi.x1 = x1; roi.x2 = x2; roi.y1 = y1; roi.y2 = y2;

    if isinf(search_max_sec)
        in_window = ~isnan(pressure_times);
    else
        in_window = pressure_times >= (detected_start - search_max_sec) & ...
            pressure_times <= (detected_end + search_max_sec);
    end
    idx = find(in_window);
    if isempty(idx)
        return;
    end

    n = numel(idx);
    dyn = empty_dynamics();
    dyn.frame_idx = pressure_frame_indices(idx);
    dyn.time = pressure_times(idx);
    dyn.cx = nan(n,1);
    dyn.cy = nan(n,1);
    dyn.area = zeros(n,1);
    dyn.total_pressure = zeros(n,1);
    dyn.mean_pressure = zeros(n,1);
    dyn.max_pressure = zeros(n,1);
    dyn.spatial_std = nan(n,1);
    dyn.global_total_pressure = zeros(n,1);
    dyn.bbox_x = repmat(x1,n,1);
    dyn.bbox_y = repmat(y1,n,1);
    dyn.bbox_w = repmat(x2-x1+1,n,1);
    dyn.bbox_h = repmat(y2-y1+1,n,1);

    raw_roi_frames = pressure_frames(y1:y2,x1:x2,idx);
    peak_frame_rel = find_peak_detected_frame_idx(cluster, pressure_times(idx));
    tracked = track_roi_component(raw_roi_frames, peak_frame_rel, ...
        [cluster.display_cx - x1 + 1, cluster.display_cy - y1 + 1], ...
        peak_fraction, component_min_area_px, component_overlap_dilate_px, ...
        component_merge_area_factor);
    [roi_rows, roi_cols] = ndgrid(y1:y2, x1:x2);
    for ii = 1:n
        crop_raw = double(raw_roi_frames(:,:,ii));
        crop = crop_raw .* tracked.mask(:,:,ii);
        frame = double(pressure_frames(:,:,idx(ii)));
        total = sum(crop(:));
        dyn.global_total_pressure(ii) = sum(frame(:));
        dyn.total_pressure(ii) = total;
        dyn.max_pressure(ii) = max(crop(:));
        if total > 0
            dyn.cx(ii) = sum(sum(crop .* roi_cols)) / total;
            dyn.cy(ii) = sum(sum(crop .* roi_rows)) / total;
            dx = roi_cols - dyn.cx(ii);
            dy = roi_rows - dyn.cy(ii);
            dyn.spatial_std(ii) = sqrt(sum(sum(crop .* (dx.^2 + dy.^2))) / total);
        end
    end

    smooth_total = smooth_pressure_trace(dyn.total_pressure, smooth_frames);
    [peak_total, peak_idx] = max(smooth_total);
    peak_pixel = max(dyn.max_pressure);
    if peak_total <= 0
        return;
    end
    threshold_total = peak_fraction * peak_total;
    threshold_pixel = peak_fraction * peak_pixel;
    above_raw = smooth_total >= threshold_total;
    above = enforce_sustained_on(above_raw, min_on_frames);
    if ~above(peak_idx)
        return;
    end

    start_idx = find_refined_start_idx(above_raw, peak_idx, off_frames);
    end_idx = find_refined_end_idx(above_raw, peak_idx, off_frames);
    spread_stop_idx = find_spatial_spread_stop_idx(dyn.spatial_std, peak_idx, ...
        std_growth_factor, std_growth_min_px, min_on_frames);
    if ~isempty(spread_stop_idx)
        end_idx = min(end_idx, spread_stop_idx - 1);
    end
    drift_stop_idx = find_centroid_drift_stop_idx(dyn, peak_idx, ...
        centroid_drift_max_px, min_on_frames);
    if ~isempty(drift_stop_idx)
        end_idx = min(end_idx, drift_stop_idx - 1);
    end
    [start_idx,end_idx] = split_distinct_contacts_in_roi(dyn, smooth_total, ...
        start_idx, end_idx, peak_idx, peak_total, split_valley_fraction, ...
        split_min_peak_fraction, split_centroid_jump_px, global_dropout_fraction, ...
        min_on_frames);

    refined_start = dyn.time(start_idx);
    refined_end = dyn.time(end_idx);
    start_truncated = ~isinf(search_max_sec) && start_idx == 1 && ...
        ~has_sustained_off_before(above_raw, peak_idx, off_frames);
    end_truncated = ~isinf(search_max_sec) && end_idx == numel(above_raw) && ...
        ~has_sustained_off_after(above_raw, peak_idx, off_frames) && isempty(spread_stop_idx);

    keep = dyn.time >= refined_start & dyn.time <= refined_end;
    kept_frame_idx = idx(keep);
    kept_mask_idx = find(keep);
    roi_frames = uint16(double(raw_roi_frames(:,:,kept_mask_idx)) .* ...
        tracked.mask(:,:,kept_mask_idx));
    fields = fieldnames(dyn);
    for fi = 1:numel(fields)
        dyn.(fields{fi}) = dyn.(fields{fi})(keep);
    end

    for ii = 1:numel(dyn.time)
        crop = double(pressure_frames(y1:y2,x1:x2,kept_frame_idx(ii)));
        active = (crop >= threshold_pixel) & tracked.mask(:,:,kept_mask_idx(ii));
        dyn.area(ii) = nnz(active);
        if dyn.area(ii) > 0
            vals = crop(active);
            dyn.mean_pressure(ii) = mean(vals);
            [active_rows, active_cols] = find(active);
            dyn.bbox_x(ii) = min(active_cols) + x1 - 1;
            dyn.bbox_y(ii) = min(active_rows) + y1 - 1;
            dyn.bbox_w(ii) = max(active_cols) - min(active_cols) + 1;
            dyn.bbox_h(ii) = max(active_rows) - min(active_rows) + 1;
        else
            dyn.mean_pressure(ii) = 0;
            dyn.bbox_x(ii) = NaN;
            dyn.bbox_y(ii) = NaN;
            dyn.bbox_w(ii) = NaN;
            dyn.bbox_h(ii) = NaN;
        end
    end
end

function [x1,x2,y1,y2]=cluster_dynamic_roi(cluster,frame_size,roi_pad_px,roi_max_size_px)
    x1 = NaN; x2 = NaN; y1 = NaN; y2 = NaN;
    if isempty(cluster.dynamics.bbox_x)
        return;
    end
    bx1 = min(cluster.dynamics.bbox_x);
    by1 = min(cluster.dynamics.bbox_y);
    bx2 = max(cluster.dynamics.bbox_x + cluster.dynamics.bbox_w - 1);
    by2 = max(cluster.dynamics.bbox_y + cluster.dynamics.bbox_h - 1);
    h = frame_size(1);
    w = frame_size(2);
    x1 = max(1, floor(bx1 - roi_pad_px));
    x2 = min(w, ceil(bx2 + roi_pad_px));
    y1 = max(1, floor(by1 - roi_pad_px));
    y2 = min(h, ceil(by2 + roi_pad_px));

    if (x2 - x1 + 1) > roi_max_size_px
        cx = median(cluster.dynamics.cx, 'omitnan');
        [x1,x2] = capped_bounds(cx, roi_max_size_px, w);
    end
    if (y2 - y1 + 1) > roi_max_size_px
        cy = median(cluster.dynamics.cy, 'omitnan');
        [y1,y2] = capped_bounds(cy, roi_max_size_px, h);
    end
end

function [lo,hi]=capped_bounds(center,max_size,limit)
    half_left = floor((max_size - 1) / 2);
    half_right = max_size - 1 - half_left;
    lo = floor(center) - half_left;
    hi = floor(center) + half_right;
    if lo < 1
        hi = hi + (1 - lo);
        lo = 1;
    end
    if hi > limit
        lo = lo - (hi - limit);
        hi = limit;
    end
    lo = max(1, lo);
    hi = min(limit, hi);
end

function peak_idx=find_peak_detected_frame_idx(cluster,window_times)
    detected_times = cluster.dynamics.time;
    detected_total = cluster.dynamics.total_pressure;
    if isempty(detected_times) || isempty(detected_total)
        peak_idx = max(1, round(numel(window_times)/2));
        return;
    end
    [~, det_peak_idx] = max(detected_total);
    seed_time = detected_times(det_peak_idx);
    [~, peak_idx] = min(abs(window_times - seed_time));
end

function tracked=track_roi_component(roi_frames,seed_idx,seed_xy,peak_fraction, ...
        min_area,overlap_dilate_px,merge_area_factor)
    n_frames = size(roi_frames, 3);
    tracked.mask = false(size(roi_frames));
    tracked.centroid = nan(n_frames, 2);

    seed_idx = max(1, min(seed_idx, n_frames));
    seed_frame = double(roi_frames(:,:,seed_idx));
    peak_pixel = max(seed_frame(:));
    if peak_pixel <= 0
        return;
    end
    threshold = peak_fraction * peak_pixel;

    [seed_mask, seed_centroid] = choose_seed_component(seed_frame, threshold, seed_xy, min_area);
    if isempty(seed_mask)
        return;
    end
    tracked.mask(:,:,seed_idx) = seed_mask;
    tracked.centroid(seed_idx,:) = seed_centroid;

    previous_mask = seed_mask;
    previous_centroid = seed_centroid;
    for fi = seed_idx-1:-1:1
        [m,c] = choose_next_component(double(roi_frames(:,:,fi)), threshold, ...
            previous_mask, previous_centroid, min_area, overlap_dilate_px, ...
            merge_area_factor);
        if isempty(m), break; end
        tracked.mask(:,:,fi) = m;
        tracked.centroid(fi,:) = c;
        previous_mask = m;
        previous_centroid = c;
    end

    previous_mask = seed_mask;
    previous_centroid = seed_centroid;
    for fi = seed_idx+1:n_frames
        [m,c] = choose_next_component(double(roi_frames(:,:,fi)), threshold, ...
            previous_mask, previous_centroid, min_area, overlap_dilate_px, ...
            merge_area_factor);
        if isempty(m), break; end
        tracked.mask(:,:,fi) = m;
        tracked.centroid(fi,:) = c;
        previous_mask = m;
        previous_centroid = c;
    end
end

function [mask,centroid]=choose_seed_component(frame,threshold,seed_xy,min_area)
    [components,centroids] = frame_components(frame, threshold, min_area);
    mask = [];
    centroid = [];
    if isempty(components)
        return;
    end
    d = hypot(centroids(:,1)-seed_xy(1), centroids(:,2)-seed_xy(2));
    [~, best] = min(d);
    mask = components{best};
    centroid = centroids(best,:);
end

function [mask,centroid]=choose_next_component(frame,threshold,previous_mask,previous_centroid, ...
        min_area,overlap_dilate_px,merge_area_factor)
    [components,centroids] = frame_components(frame, threshold, min_area);
    mask = [];
    centroid = [];
    if isempty(components)
        return;
    end
    allowed_previous = previous_mask;
    if overlap_dilate_px > 0
        allowed_previous = imdilate(previous_mask, strel('disk', overlap_dilate_px));
    end
    overlaps = zeros(numel(components),1);
    for ci = 1:numel(components)
        overlaps(ci) = nnz(components{ci} & allowed_previous);
    end
    if ~any(overlaps > 0)
        return;
    end
    [~, best] = max(overlaps);

    previous_area = nnz(previous_mask);
    candidate_area = nnz(components{best});
    centroid_jump = hypot(centroids(best,1)-previous_centroid(1), ...
        centroids(best,2)-previous_centroid(2));
    if previous_area > 0 && candidate_area > merge_area_factor * previous_area && ...
            centroid_jump > 2
        return;
    end
    mask = components{best};
    centroid = centroids(best,:);
end

function [components,centroids,areas]=frame_components(frame,threshold,min_area)
    bw = frame >= threshold;
    cc = bwconncomp(bw);
    props = regionprops(cc, frame, 'Area', 'WeightedCentroid');
    keep = find([props.Area] >= min_area);
    components = cell(numel(keep),1);
    centroids = nan(numel(keep),2);
    areas = zeros(numel(keep),1);
    for ii = 1:numel(keep)
        pi = keep(ii);
        m = false(size(frame));
        m(cc.PixelIdxList{pi}) = true;
        components{ii} = m;
        centroids(ii,:) = props(pi).WeightedCentroid;
        areas(ii) = props(pi).Area;
    end
end

function y=smooth_pressure_trace(x,window_size)
    window_size = max(1, round(window_size));
    if window_size <= 1 || numel(x) < 3
        y = x;
    else
        y = movmean(x, window_size, 'omitnan');
    end
end

function sustained=enforce_sustained_on(above,min_on_frames)
    min_on_frames = max(1, round(min_on_frames));
    sustained = false(size(above));
    if min_on_frames <= 1
        sustained = above;
        return;
    end
    d = diff([false; above(:); false]);
    starts = find(d == 1);
    stops = find(d == -1) - 1;
    for i = 1:numel(starts)
        if (stops(i) - starts(i) + 1) >= min_on_frames
            sustained(starts(i):stops(i)) = true;
        end
    end
end

function start_idx=find_refined_start_idx(above,peak_idx,off_frames)
    off_frames = max(1, round(off_frames));
    start_idx = 1;
    for i = peak_idx:-1:1
        run_start = max(1, i - off_frames + 1);
        if all(~above(run_start:i))
            start_idx = min(i + 1, peak_idx);
            return;
        end
    end
end

function end_idx=find_refined_end_idx(above,peak_idx,off_frames)
    off_frames = max(1, round(off_frames));
    end_idx = numel(above);
    for i = peak_idx:numel(above)
        run_end = min(numel(above), i + off_frames - 1);
        if (run_end - i + 1) == off_frames && all(~above(i:run_end))
            end_idx = max(peak_idx, i - 1);
            return;
        end
    end
end

function tf=has_sustained_off_before(above,peak_idx,off_frames)
    tf = find_refined_start_idx(above,peak_idx,off_frames) > 1;
end

function tf=has_sustained_off_after(above,peak_idx,off_frames)
    tf = find_refined_end_idx(above,peak_idx,off_frames) < numel(above);
end

function stop_idx=find_spatial_spread_stop_idx(spatial_std,peak_idx,growth_factor,growth_min_px,min_frames)
    stop_idx = [];
    peak_std = spatial_std(peak_idx);
    if isnan(peak_std) || peak_std <= 0
        return;
    end
    limit = max(peak_std * growth_factor, peak_std + growth_min_px);
    too_wide = spatial_std > limit;
    min_frames = max(1, round(min_frames));
    for i = peak_idx:numel(too_wide)
        run_end = min(numel(too_wide), i + min_frames - 1);
        if (run_end - i + 1) == min_frames && all(too_wide(i:run_end))
            stop_idx = i;
            return;
        end
    end
end

function stop_idx=find_centroid_drift_stop_idx(dyn,peak_idx,max_drift_px,min_frames)
    stop_idx = [];
    peak_x = dyn.cx(peak_idx);
    peak_y = dyn.cy(peak_idx);
    if isnan(peak_x) || isnan(peak_y)
        return;
    end
    drift = hypot(dyn.cx - peak_x, dyn.cy - peak_y);
    too_far = drift > max_drift_px;
    min_frames = max(1, round(min_frames));
    for i = peak_idx:numel(too_far)
        run_end = min(numel(too_far), i + min_frames - 1);
        if (run_end - i + 1) == min_frames && all(too_far(i:run_end))
            stop_idx = i;
            return;
        end
    end
end

function [start_idx,end_idx]=split_distinct_contacts_in_roi(dyn,smooth_total, ...
        start_idx,end_idx,peak_idx,peak_total,valley_fraction,min_peak_fraction, ...
        centroid_jump_px,global_dropout_fraction,window_frames)
    global_peak = max(dyn.global_total_pressure);
    dropout_thresh = global_dropout_fraction * global_peak;

    pre_valley = find_split_valley_before_peak(dyn, smooth_total, start_idx, ...
        peak_idx, peak_total, valley_fraction, min_peak_fraction, ...
        centroid_jump_px, dropout_thresh, window_frames);
    if ~isempty(pre_valley)
        start_idx = max(start_idx, pre_valley + 1);
    end

    post_valley = find_split_valley_after_peak(dyn, smooth_total, peak_idx, ...
        end_idx, peak_total, valley_fraction, min_peak_fraction, ...
        centroid_jump_px, dropout_thresh, window_frames);
    if ~isempty(post_valley)
        end_idx = min(end_idx, post_valley - 1);
    end
end

function valley_idx=find_split_valley_after_peak(dyn,smooth_total,peak_idx,end_idx, ...
        peak_total,valley_fraction,min_peak_fraction,centroid_jump_px, ...
        dropout_thresh,window_frames)
    valley_idx = [];
    if end_idx <= peak_idx + 2 * window_frames
        return;
    end
    for i = peak_idx + window_frames : end_idx - window_frames
        if dyn.global_total_pressure(i) <= dropout_thresh
            continue;
        end
        post_peak = max(smooth_total(i+1:end_idx));
        smaller_peak = min(peak_total, post_peak);
        if post_peak < min_peak_fraction * peak_total
            continue;
        end
        if smooth_total(i) > valley_fraction * smaller_peak
            continue;
        end
        if centroid_jump_across_valley(dyn, i, window_frames) < centroid_jump_px
            continue;
        end
        valley_idx = i;
        return;
    end
end

function valley_idx=find_split_valley_before_peak(dyn,smooth_total,start_idx,peak_idx, ...
        peak_total,valley_fraction,min_peak_fraction,centroid_jump_px, ...
        dropout_thresh,window_frames)
    valley_idx = [];
    if peak_idx <= start_idx + 2 * window_frames
        return;
    end
    for i = peak_idx - window_frames : -1 : start_idx + window_frames
        if dyn.global_total_pressure(i) <= dropout_thresh
            continue;
        end
        pre_peak = max(smooth_total(start_idx:i-1));
        smaller_peak = min(peak_total, pre_peak);
        if pre_peak < min_peak_fraction * peak_total
            continue;
        end
        if smooth_total(i) > valley_fraction * smaller_peak
            continue;
        end
        if centroid_jump_across_valley(dyn, i, window_frames) < centroid_jump_px
            continue;
        end
        valley_idx = i;
        return;
    end
end

function jump=centroid_jump_across_valley(dyn,valley_idx,window_frames)
    before_idx = max(1, valley_idx-window_frames):max(1, valley_idx-1);
    after_idx = min(numel(dyn.cx), valley_idx+1):min(numel(dyn.cx), valley_idx+window_frames);
    before_x = median(dyn.cx(before_idx), 'omitnan');
    before_y = median(dyn.cy(before_idx), 'omitnan');
    after_x = median(dyn.cx(after_idx), 'omitnan');
    after_y = median(dyn.cy(after_idx), 'omitnan');
    jump = hypot(after_x-before_x, after_y-before_y);
    if isnan(jump)
        jump = 0;
    end
end

function clean_events=build_clean_gait_events(events,swing_min_sec,max_merge_dist_px,min_stance_sec)
    % Noise is retained in raw footstep_events for auditability, but must
    % never enter the paw-specific clean gait series.
    keep_label = ismember({events.label}, {'FL','FR','HL','HR'});
    events = events(keep_label);
    valid_duration = [events.duration] >= min_stance_sec;
    events = events(valid_duration);

    labels = unique({events.label}, 'stable');
    clean_events = repmat(empty_clean_event(), 0, 1);
    for li = 1:numel(labels)
        paw_events = events(strcmp({events.label}, labels{li}));
        [~, order] = sort([paw_events.start_time]);
        paw_events = paw_events(order);

        for ei = 1:numel(paw_events)
            if isempty(clean_events) || ~strcmp(clean_events(end).label, labels{li})
                clean_events(end+1,1) = event_to_clean_event(paw_events(ei), 'kept'); %#ok<AGROW>
                continue;
            end

            gap = paw_events(ei).start_time - clean_events(end).end_time;
            dist = hypot(paw_events(ei).centroid_x - clean_events(end).centroid_x, ...
                paw_events(ei).centroid_y - clean_events(end).centroid_y);
            if gap < swing_min_sec && dist <= max_merge_dist_px
                clean_events(end) = merge_clean_events(clean_events(end), paw_events(ei));
            else
                % Events of the same paw that are not merged (gap of at
                % least swing_min_sec or centroid shift above
                % max_merge_dist_px) are kept as separate stance events.
                clean_events(end+1,1) = event_to_clean_event(paw_events(ei), 'kept'); %#ok<AGROW>
            end
        end
    end
end

function clean=empty_clean_event()
    clean = struct('label','','cluster_ids',[],'start_time',[],'end_time',[], ...
        'duration',[],'centroid_x',[],'centroid_y',[],'n_obs',[], ...
        'representative_cluster_id',[],'clean_status','');
end

function clean=event_to_clean_event(event,status)
    clean = empty_clean_event();
    clean.label = event.label;
    clean.cluster_ids = event.cluster_id;
    clean.start_time = event.start_time;
    clean.end_time = event.end_time;
    clean.duration = event.duration;
    clean.centroid_x = event.centroid_x;
    clean.centroid_y = event.centroid_y;
    clean.n_obs = event.n_obs;
    clean.representative_cluster_id = event.cluster_id;
    clean.clean_status = status;
end

function clean=merge_clean_events(clean,event)
    old_weight = max(clean.n_obs, 0);
    new_weight = max(event.n_obs, 0);
    total_weight = old_weight + new_weight;
    clean.cluster_ids(end+1) = event.cluster_id;
    clean.end_time = max(clean.end_time, event.end_time);
    clean.duration = clean.end_time - clean.start_time;
    if total_weight > 0
        clean.centroid_x = (clean.centroid_x * old_weight + event.centroid_x * new_weight) / total_weight;
        clean.centroid_y = (clean.centroid_y * old_weight + event.centroid_y * new_weight) / total_weight;
    end
    clean.n_obs = clean.n_obs + event.n_obs;
    clean.clean_status = 'merged';
end

function [events,clean_events]=mark_clean_event_representatives(events,clean_events)
    for ei = 1:numel(events)
        if events(ei).valid_stance
            events(ei).clean_status = 'clean_rejected';
        else
            events(ei).clean_status = 'invalid_duration_or_truncated';
        end
        events(ei).valid_stance = false;
    end

    for ci = 1:numel(clean_events)
        cids = clean_events(ci).cluster_ids;
        event_idx = find(ismember([events.cluster_id], cids));
        if isempty(event_idx)
            continue;
        end
        [~, best_local] = max([events(event_idx).n_obs]);
        rep_idx = event_idx(best_local);
        rep_id = events(rep_idx).cluster_id;
        clean_events(ci).representative_cluster_id = rep_id;

        for k = 1:numel(event_idx)
            if event_idx(k) == rep_idx
                events(event_idx(k)).valid_stance = true;
                events(event_idx(k)).clean_status = clean_events(ci).clean_status;
            else
                events(event_idx(k)).valid_stance = false;
                events(event_idx(k)).clean_status = sprintf('merged_into_%d', rep_id);
            end
        end
    end
end
