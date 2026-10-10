function results = s2_detect_contacts(only, opts)
% Tail-base CNN on the overhead video, then the contact detector: writes the
% pressure movie and contacts with camera votes to dynamics/<recording>/.

if nargin < 1, only = []; end
if nargin < 2, opts = struct(); end
[cfg, R] = gait_config(only);
overwrite = isfield(opts, 'overwrite') && opts.overwrite;
if isempty(R), error('No matching enabled recordings in %s.', cfg.recording_list_path); end

results = table(R.output_name, strings(height(R), 1), strings(height(R), 1), ...
    'VariableNames', {'output_name', 'status', 'message'});
for i = 1:height(R)
    rec = R(i, :);
    out_dir = fullfile(cfg.dynamics_root, rec.output_name);
    ensure_dir(out_dir);
    [~, base] = fileparts(rec.input_file);
    dyn_path = fullfile(out_dir, base + "_peak_seed_footstep_dynamics.mat");
    pred_path = fullfile(out_dir, 'square_tailbase_predictions.csv');
    fprintf('[%d/%d] %s\n', i, height(R), rec.output_name);
    try
        for f = ["input_file", "camera1_path", "homography_path", "background_path"]
            if ~isfile(rec.(f)), error('Missing %s: %s', f, rec.(f)); end
        end
        if overwrite || ~isfile(pred_path)
            predict_tailbase(cfg, rec, out_dir);
        end
        if ~overwrite && isfile(dyn_path) && dir(dyn_path).datenum >= dir(pred_path).datenum
            results.status(i) = "skipped"; results.message(i) = "existing dynamics file";
            continue;
        end
        ensure_dir(cfg.log_root);
        diary(fullfile(cfg.log_root, base + "_peak_seed.log"));
        run_detector(cfg, rec, out_dir);
        diary('off');
        results.status(i) = "done"; results.message(i) = "OK";
    catch ME
        diary('off');
        results.status(i) = "failed"; results.message(i) = string(ME.message);
        fprintf(2, 'FAILED %s: %s\n', rec.output_name, ME.message);
    end
end
ensure_dir(cfg.summary_root);
writetable(results, fullfile(cfg.summary_root, 's2_detect_contacts_results.csv'));
end

function run_detector(cfg, rec, out_dir)
% The detector script reads SEGMENTATION_* variables; these are the paper's settings.
S = struct( ...
    'input_file', char(rec.input_file), 'output_dir', char(out_dir), ...
    'video_cam1_path', char(rec.camera1_path), ...
    'homography_path', char(rec.homography_path), ...
    'background_path', char(rec.background_path), ...
    'save_video', false, 'show_figure', false, 'playback_speed', Inf, ...
    'video_sample_fps_override', 30, ...
    'layout', 'runway', 'pressure_width', 256, 'pressure_height', 64, ...
    'layout_board_ids', [4 3 2 1], ...
    'transforms_by_id', {{'none', 'none', 'none', 'none'}}, ...
    'debug_footprint_candidates', false, 'print_raw_cluster_summary', false, ...
    'min_contact_area', 5, 'peak_seed_candidate_mode', 'binary', ...
    'prelabel_merge_dist_px', 8, 'prelabel_merge_edge_gap_px', 6, ...
    'prelabel_merge_dilate_radius_px', 4, 'prelabel_merge_max_area', 120, ...
    'prelabel_merge_seam_max_area', 240, 'prelabel_merge_debug', false, ...
    'swing_min_sec', 0.10, 'gait_merge_max_dist_px', 15, ...
    'gait_min_stance_sec', 0.08, 'dynamic_roi_max_size_px', 32, ...
    'pre_refinement_group_enabled', true);
f = fieldnames(S);
for k = 1:numel(f)
    eval(['SEGMENTATION_' upper(f{k}) ' = S.(f{k});']);
end
old = cd(cfg.detector_dir);
restore = onCleanup(@() cd(old));
run(cfg.detector_script);
end

function predict_tailbase(cfg, rec, out_dir)
% Board-space RGB + body-mask frames for the tail-base CNN, then predict.
sample_fps = 30; bg_diff_thresh = 100; min_blob_area = 27903; board_w = 256; board_h = 64;
input_root = fullfile(out_dir, 'tailbase_inputs');
rgb_dir = fullfile(input_root, 'rgb'); mask_dir = fullfile(input_root, 'mask');
ensure_dir(rgb_dir); ensure_dir(mask_dir);
manifest_path = fullfile(input_root, 'square_tailbase_manifest.csv');
camera_prediction_path = fullfile(out_dir, 'square_tailbase_predictions_camera.csv');
prediction_path = fullfile(out_dir, 'square_tailbase_predictions.csv');

data = load(rec.input_file, 'camera1_frame_timestamps');
hom = load(rec.homography_path, 'tform');
bg = load(rec.background_path, 'bg_model');
bg_gray = rgb2gray(bg.bg_model);
cam = VideoReader(rec.camera1_path);
timestamps = data.camera1_frame_timestamps(:);
n_frames = min(cam.NumFrames, numel(timestamps));
out_ref = imref2d([board_h, board_w], [0 board_w], [0 board_h]);

rows = {};
last_t = -Inf;
for frame_idx = 1:n_frames
    frame = readFrame(cam);
    t = double(timestamps(frame_idx));
    if t - last_t < (1 / sample_fps) && frame_idx < n_frames, continue; end
    frame_rot = rot90(frame, 2);
    mask = abs(double(rgb2gray(frame_rot)) - double(bg_gray)) > bg_diff_thresh;
    mask = imclose(mask, strel('disk', 4));
    mask = imopen(mask, strel('disk', 3));
    mask = imfill(mask, 'holes');
    mask = bwareaopen(mask, min_blob_area);
    board_rgb = imwarp(frame_rot, hom.tform, 'OutputView', out_ref, 'Interp', 'linear');
    board_mask = largest_component(imwarp(mask, hom.tform, 'OutputView', out_ref, 'Interp', 'nearest'));
    stem = sprintf('frame_%06d', frame_idx);
    rgb_path = fullfile(rgb_dir, [stem '.png']);
    mask_path = fullfile(mask_dir, [stem '.png']);
    imwrite(board_rgb, rgb_path);
    imwrite(uint8(board_mask) * 255, mask_path);
    sid = sprintf('square_pred_%06d', frame_idx);
    rows(end+1, :) = {sid, sid, "prediction", frame_idx, t, rgb_path, mask_path, ...
        size(frame_rot, 2), size(frame_rot, 1), board_w, board_h, 1, 1}; %#ok<AGROW>
    last_t = t;
end
writetable(cell2table(rows, 'VariableNames', {'sample_id', 'event_uid', 'output_name', ...
    'frame_index', 'time_s', 'rgb_path', 'mask_path', 'camera_width_px', 'camera_height_px', ...
    'image_width_px', 'image_height_px', 'image_to_camera_scale_x', 'image_to_camera_scale_y'}), ...
    manifest_path);
fprintf('  tail-base inputs: %d frames\n', size(rows, 1));

cmd = sprintf('"%s" "%s" predict --manifest "%s" --checkpoint "%s" --out "%s" --batch-size 32 --decode soft', ...
    cfg.python_exe, cfg.tailbase_script, manifest_path, cfg.tailbase_checkpoint, camera_prediction_path);
if system(cmd, '-echo') ~= 0, error('Tail-base prediction failed.'); end
T = readtable(camera_prediction_path, 'TextType', 'string', 'Delimiter', ',', 'VariableNamingRule', 'preserve');
writetable(T(:, {'frame_index', 'time_s', 'tailbase_x_px', 'tailbase_y_px', 'tailbase_confidence'}), ...
    prediction_path);
end

function mask = largest_component(mask)
cc = bwconncomp(mask);
if cc.NumObjects == 0, return; end
[~, k] = max(cellfun(@numel, cc.PixelIdxList));
mask(:) = false;
mask(cc.PixelIdxList{k}) = true;
end

function ensure_dir(p)
if ~exist(p, 'dir'), mkdir(p); end
end
