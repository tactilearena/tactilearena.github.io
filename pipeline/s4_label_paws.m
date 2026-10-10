% Combines the pressure movie from step 2 and the mobile window from step 3
% and generate the final footprint assignment 

function results = s4_label_paws(only, opts)

if nargin < 1, only = []; end
if nargin < 2, opts = struct(); end
[cfg, R] = gait_config(only);
vid = struct('on', false, 'still', false, 'max_bouts', Inf);
if isfield(opts, 'video'), vid.on = logical(opts.video); end
if isfield(opts, 'video_still'), vid.still = logical(opts.video_still); vid.on = vid.on || vid.still; end
if isfield(opts, 'video_max_bouts'), vid.max_bouts = opts.video_max_bouts; end
opts = rmfield(opts, intersect(fieldnames(opts), {'video', 'video_still', 'video_max_bouts'}));
src = 'curated';
if isfield(opts, 'bouts'), src = opts.bouts; opts = rmfield(opts, 'bouts'); end
W = table();
if strcmp(src, 'curated'), src = cfg.bout_windows_path; end
if ~strcmp(src, 'auto')
    W = readtable(src, 'TextType', 'string', 'Delimiter', ',', 'VariableNamingRule', 'preserve');
end
if ~exist(cfg.contacts_root, 'dir'), mkdir(cfg.contacts_root); end
results = table(R.output_name, zeros(height(R), 1), zeros(height(R), 1), strings(height(R), 1), ...
    'VariableNames', {'output_name', 'n_bouts', 'n_contacts', 'status'});
for i = 1:height(R)
    rec = R.output_name(i);
    dm = dir(fullfile(cfg.dynamics_root, rec, '*_peak_seed_footstep_dynamics.mat'));
    if isempty(dm), results.status(i) = "no s2 output"; continue; end
    D = load(fullfile(dm(1).folder, dm(1).name), 'footstep_events', ...
        'pressure_movie_frames', 'pressure_movie_times');
    o = opts;
    if ~isempty(W)
        Wr = W(W.recording == rec, :);
        if isempty(Wr), results.status(i) = "no bouts"; continue; end
        o.bout_windows = [Wr.t_start, Wr.t_end];
    end
    [contacts, info] = label_mobile_footsteps(D.footstep_events, D.pressure_movie_frames, ...
        D.pressure_movie_times, o);
    bout_windows = info.bout_windows; %#ok<NASGU>
    save(fullfile(cfg.contacts_root, rec + "_mobile_contacts.mat"), 'contacts', 'info', 'bout_windows');
    results.n_bouts(i) = size(info.bout_windows, 1);
    results.n_contacts(i) = numel(contacts);
    results.status(i) = "done";
    fprintf('[%d/%d] %s: %d bouts, %d contacts\n', i, height(R), rec, results.n_bouts(i), numel(contacts));
    if vid.on
        write_label_video(cfg, R(i, :), D, contacts, info.bout_windows, vid);
    end
end
end

function out_path = write_label_video(cfg, rec, D, contacts, W, vid)
% Create the overlaid overhead camera + pressure reco for each walking window
PAWS = ["FL", "FR", "HL", "HR"];
PAW_RGB = [0.18 0.66 0.31; 0.95 0.42 0.23; 0.23 0.51 0.96; 0.95 0.76 0.18];
pad_s = 0.3; video_fps = 30;
name = rec.output_name;
t_p = double(D.pressure_movie_times(:));
contacts = contacts([contacts.mobile_valid]);

% manual labels, for disagreement tags
human = strings(numel(contacts), 1);
hf = fullfile(cfg.blind_labels_dir, name + "_blind_" + cfg.labeler_id + ".csv");
if isfile(hf)
    H = readtable(hf, 'TextType', 'string', 'Delimiter', ',');
    H = H(ismember(H.label, PAWS), :); hm = 0.5 * (H.start_time + H.end_time);
    for k = 1:numel(contacts)
        j = find(hm >= contacts(k).start_time - 0.05 & hm <= contacts(k).end_time + 0.05 & ...
            hypot(H.centroid_x - contacts(k).centroid_x, H.centroid_y - contacts(k).centroid_y) <= 15);
        if ~isempty(j)
            [~, q] = min(hypot(H.centroid_x(j) - contacts(k).centroid_x, H.centroid_y(j) - contacts(k).centroid_y));
            human(k) = H.label(j(q));
        end
    end
end

% camera timestamps on the pressure time base: t0 = min(first camera-1
% timestamp, first board timestamp), as in the detector
raw = load(rec.input_file, 'camera0_frame_timestamps', 'camera1_frame_timestamps', ...
    'Board1_timestamps', 'Board2_timestamps', 'Board3_timestamps', 'Board4_timestamps');
t0 = double(raw.camera1_frame_timestamps(1));
for b = 1:4
    f = sprintf('Board%d_timestamps', b);
    if isfield(raw, f)
        ts = raw.(f); if iscell(ts), ts = cell2mat(ts); end
        t0 = min(t0, double(ts(1)));
    end
end
if contains(rec.camera1_path, "camera_0")
    cam_ts = double(raw.camera0_frame_timestamps(:)) - t0;
else
    cam_ts = double(raw.camera1_frame_timestamps(:)) - t0;
end
vr = VideoReader(rec.camera1_path);
hom = load(rec.homography_path, 'tform');
P_H = size(D.pressure_movie_frames, 1); P_W = size(D.pressure_movie_frames, 2);
[bx, by] = transformPointsInverse(hom.tform, [0.5 P_W+0.5 P_W+0.5 0.5]', [0.5 0.5 P_H+0.5 P_H+0.5]');
margin = 60;
crop = round([max(1, min(bx) - margin), max(1, min(by) - margin), ...
    min(vr.Width, max(bx) + margin), min(vr.Height, max(by) + margin)]);

[XX, YY] = meshgrid(1:P_W, 1:P_H);
fs = 1 / median(diff(t_p));
rend = false(numel(t_p), 1);
nb = min(size(W, 1), vid.max_bouts);
for b = 1:nb, rend = rend | (t_p >= W(b, 1) - pad_s & t_p <= W(b, 2) + pad_s); end
fidx = find(rend);
copx = nan(numel(t_p), 1); copy = copx;
for f = fidx'
    fr = double(D.pressure_movie_frames(:, :, f)); m = fr > 200;
    if any(m(:)), w = fr(m); copx(f) = sum(XX(m) .* w) / sum(w); copy(f) = sum(YY(m) .* w) / sum(w); end
end
win = max(1, round(0.3 * fs));
scopx = movmean(copx, win, 'omitnan'); scopy = movmean(copy, win, 'omitnan');
c_t0 = [contacts.start_time]'; c_t1 = [contacts.end_time]';
c_x = [contacts.centroid_x]'; c_y = [contacts.centroid_y]';
c_lab = string({contacts.label})';
[c_cx, c_cy] = transformPointsInverse(hom.tform, c_x, c_y);

FW = 1280; cam_h = round(1240 * (crop(4) - crop(2) + 1) / (crop(3) - crop(1) + 1));
pr_h = round(1240 * P_H / P_W); FH = 20 + pr_h + 16 + cam_h + 44;
fig = figure('Visible', 'off', 'Color', [0.08 0.08 0.08], 'Units', 'pixels', 'Position', [50 50 FW FH]);
restore = onCleanup(@() close(fig));
ax_p = axes(fig, 'Units', 'pixels', 'Position', [20 20 1240 pr_h]);
ax_c = axes(fig, 'Units', 'pixels', 'Position', [20 20 + pr_h + 16 1240 cam_h]);
title_h = annotation(fig, 'textbox', [0.012, 1 - 40 / FH, 0.6, 36 / FH], 'String', '', 'Color', 'w', ...
    'EdgeColor', 'none', 'FontSize', 11, 'FontName', 'Arial', 'Interpreter', 'none', 'VerticalAlignment', 'middle');
for li = 1:4
    annotation(fig, 'textbox', [0.64 + 0.085 * (li - 1), 1 - 40 / FH, 0.085, 36 / FH], 'String', char(PAWS(li)), ...
        'VerticalAlignment', 'middle', 'Color', PAW_RGB(li, :), 'EdgeColor', 'none', 'FontSize', 14, ...
        'FontWeight', 'bold', 'FontName', 'Arial', 'HorizontalAlignment', 'center');
end

if vid.still
    act_n = arrayfun(@(f) nnz(c_t0 <= t_p(f) & c_t1 >= t_p(f)), fidx);
    fi = find(act_n >= 3, 1); if isempty(fi), fi = 1; end
    fidx = fidx(fi);
    out_path = fullfile(cfg.contacts_root, name + "_paw_labels_still.png");
else
    out_path = fullfile(cfg.contacts_root, name + "_paw_labels.mp4");
    vw = VideoWriter(char(out_path), 'MPEG-4');
    vw.FrameRate = video_fps; vw.Quality = 90;
    open(vw);
end
last_ci = -1; cam_img = [];
for n = 1:numel(fidx)
    f = fidx(n); t = t_p(f);
    [~, ci] = min(abs(cam_ts - t));
    ci = min(max(ci, 1), vr.NumFrames);
    if ci ~= last_ci
        cam_img = rot90(read(vr, ci), 2);
        cam_img = cam_img(crop(2):crop(4), crop(1):crop(3), :);
        last_ci = ci;
    end
    act = find(c_t0 <= t & c_t1 >= t);
    bout = find(t >= W(:, 1) & t <= W(:, 2), 1);
    cla(ax_c); image(ax_c, cam_img); axis(ax_c, 'image', 'off'); hold(ax_c, 'on');
    plot(ax_c, [bx; bx(1)] - crop(1) + 1, [by; by(1)] - crop(2) + 1, '-', 'Color', [1 1 1 0.35], 'LineWidth', 1);
    cla(ax_p);
    imagesc(ax_p, double(D.pressure_movie_frames(:, :, f)), [0 1500]); colormap(ax_p, gray(256));
    axis(ax_p, 'image', 'off'); hold(ax_p, 'on');
    k0 = max(1, f - round(1.0 * fs));
    plot(ax_p, scopx(k0:f), scopy(k0:f), '-', 'Color', [0.85 0.85 0.85 0.6], 'LineWidth', 1.2);
    plot(ax_p, scopx(f), scopy(f), 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', 'k');
    for a = act'
        col = PAW_RGB(PAWS == c_lab(a), :);
        plot(ax_p, c_x(a), c_y(a), 'o', 'MarkerSize', 22, 'LineWidth', 2.5, 'Color', col);
        text(ax_p, c_x(a), c_y(a) - 8, char(c_lab(a)), 'Color', col, 'FontSize', 12, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'FontName', 'Arial');
        if strlength(human(a)) > 0 && human(a) ~= c_lab(a)
            text(ax_p, c_x(a), c_y(a) + 8, "human: " + human(a), 'Color', [1 1 1], 'FontSize', 9, ...
                'HorizontalAlignment', 'center', 'FontName', 'Arial');
        end
        px = c_cx(a) - crop(1) + 1; py = c_cy(a) - crop(2) + 1;
        plot(ax_c, px, py, 'o', 'MarkerSize', 16, 'LineWidth', 3, 'Color', col);
        text(ax_c, px, py - 26, char(c_lab(a)), 'Color', col, 'FontSize', 14, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'FontName', 'Arial');
    end
    if isempty(bout), bs = 'between windows'; else, bs = sprintf('walking window %d/%d', bout, nb); end
    title_h.String = sprintf('%s   t = %6.2f s   %s   (~%.2fx speed)', name, t, bs, video_fps / fs);
    drawnow;
    if vid.still
        exportgraphics(fig, out_path, 'Resolution', 150, 'BackgroundColor', 'current');
    else
        writeVideo(vw, getframe(fig));
    end
end
if ~vid.still, close(vw); end
fprintf('  saved %s\n', out_path);
end

function [contacts, info] = label_mobile_footsteps(footstep_events, frames, times, opts)

if nargin < 4 || isempty(opts), opts = struct(); end
vote_px = 8; merge_px = 6; merge_gap = 0.06;
if isfield(opts, 'vote_px'), vote_px = opts.vote_px; end
if isfield(opts, 'merge_px'), merge_px = opts.merge_px; end
if isfield(opts, 'merge_gap_s'), merge_gap = opts.merge_gap_s; end

W = [];
if isfield(opts, 'bout_windows'), W = opts.bout_windows; end
if isempty(W)
    [t_ds, is_moving] = mobile_bout_mask(frames, times);
    d = diff([false; logical(is_moving(:)); false]);
    W = [t_ds(d(1:end-1) == 1), t_ds(find(d == -1) - 1)];
end

contacts = track_mobile_contacts(frames, times, W, opts);
n = numel(contacts);
qv = zeros(n, 4);
if ~isempty(footstep_events) && n > 0
    ok = arrayfun(@(e) ~isempty(e.start_time) && ~isempty(e.end_time) && ~isempty(e.quad_votes), footstep_events(:));
    fe = footstep_events(ok);
    ft0 = [fe.start_time]'; ft1 = [fe.end_time]'; fx = [fe.centroid_x]'; fy = [fe.centroid_y]';
    for k = 1:n
        j = find(ft0 < contacts(k).end_time & ft1 > contacts(k).start_time);
        if isempty(j), continue; end
        [dm, q] = min(hypot(fx(j) - contacts(k).centroid_x, fy(j) - contacts(k).centroid_y));
        if dm <= vote_px
            v = double(fe(j(q)).quad_votes(:)'); v(end+1:4) = 0; qv(k, :) = v(1:4);
        end
    end
end
for k = 1:n, contacts(k).quad_votes = qv(k, :); end

ao = opts; ao.bout_windows = W;
[contacts, ainfo] = assign_mobile_paw_labels(contacts, frames, times, ao);
in_bout = [contacts.mobile_in_bout]';
contacts = contacts(in_bout);
for k = 1:numel(contacts)
    contacts(k).label = contacts(k).mobile_label;
end
[contacts, n_merged] = merge_same_paw_pieces(contacts, merge_px, merge_gap);
mid = 0.5 * ([contacts.start_time]' + [contacts.end_time]');
for k = 1:numel(contacts)
    contacts(k).bout_index = find(mid(k) >= W(:, 1) & mid(k) <= W(:, 2), 1);
end
info = struct('bout_windows', W, 'n_contacts', numel(contacts), ...
    'n_with_camera_votes', nnz(any(qv(in_bout, :) > 0, 2)), ...
    'n_same_paw_pieces_merged', n_merged, 'assign', ainfo);
end

function [c, n_merged] = merge_same_paw_pieces(c, merge_px, merge_gap)
% One stance cut in two by a mid-stance pressure dip (the valley split is
% meant for fore-to-hind handoffs): same label, same spot, back to back.
n_merged = 0;
if numel(c) < 2, return; end
[~, o] = sort([c.start_time]); c = c(o);
k = 1;
while k < numel(c)
    j = k + 1;
    merged = false;
    while j <= numel(c) && c(j).start_time <= c(k).end_time + merge_gap
        if c(j).mobile_valid && c(k).mobile_valid && strcmp(c(j).label, c(k).label) && ...
                c(j).start_time >= c(k).end_time - 1e-9 && ...
                hypot(c(j).centroid_x - c(k).centroid_x, c(j).centroid_y - c(k).centroid_y) <= merge_px
            a = c(k).track; b = c(j).track;
            f = fieldnames(a);
            for q = 1:numel(f), a.(f{q}) = [a.(f{q}); b.(f{q})]; end
            w = a.total_pressure;
            c(k).track = a;
            c(k).end_time = c(j).end_time; c(k).end_frame = c(j).end_frame;
            c(k).duration = c(k).end_time - c(k).start_time;
            c(k).centroid_x = sum(a.cx .* w) / sum(w); c(k).centroid_y = sum(a.cy .* w) / sum(w);
            c(k).dynamic_peak_total_pressure = max(w);
            c(k).mobile_margin = min(c(k).mobile_margin, c(j).mobile_margin);
            c(j) = [];
            n_merged = n_merged + 1; merged = true;
            break;
        end
        j = j + 1;
    end
    if ~merged, k = k + 1; end
end
end

function contacts = track_mobile_contacts(frames, times, bout_windows, opts)
% search through footprints within the mobile window and spatiotemporally 
% link the pressure clusters over time
if nargin < 4 || isempty(opts), opts = struct(); end
thresh = get_opt(opts, 'pressure_thresh', 200);
link_px = get_opt(opts, 'link_px', 4);
max_gap = get_opt(opts, 'max_gap_frames', 3);
join_px = get_opt(opts, 'join_px', 4);
join_gap = get_opt(opts, 'join_gap_s', 0.05);
valley_frac = get_opt(opts, 'valley_frac', 0.5);
min_dur = get_opt(opts, 'min_dur_s', 0.10);
min_peak = get_opt(opts, 'min_peak', 4e4);
pad = get_opt(opts, 'bout_pad_s', 0.5);

t = double(times(:));
scan = false(numel(t), 1);
for b = 1:size(bout_windows, 1)
    scan = scan | (t >= bout_windows(b, 1) - pad & t <= bout_windows(b, 2) + pad);
end
[XX, YY] = meshgrid(1:size(frames, 2), 1:size(frames, 1));
se = true(3);

tr = struct('f', {}, 'x', {}, 'y', {}, 'w', {}, 'a', {});
last_f = zeros(0, 1); last_x = zeros(0, 1); last_y = zeros(0, 1); act = zeros(0, 1);
for f = find(scan)'
    fr = double(frames(:, :, f));
    m = fr > thresh;
    blobs = zeros(0, 4);
    if any(m(:))
        cc = bwconncomp(imdilate(m, se), 8);
        blobs = zeros(cc.NumObjects, 4);
        for j = 1:cc.NumObjects
            px = cc.PixelIdxList{j}; px = px(m(px));
            if isempty(px), continue; end
            w = fr(px); s = sum(w);
            blobs(j, :) = [sum(XX(px) .* w) / s, sum(YY(px) .* w) / s, s, numel(px)];
        end
        blobs = blobs(blobs(:, 3) > 0, :);
    end
    keep_act = f - last_f(act) <= max_gap + 1;
    act = act(keep_act);
    used = false(size(blobs, 1), 1);
    if ~isempty(act) && ~isempty(blobs)
        Dm = hypot(last_x(act) - blobs(:, 1)', last_y(act) - blobs(:, 2)');
        while true
            [dmin, idx] = min(Dm(:));
            if isempty(dmin) || dmin > link_px, break; end
            [ai, bi] = ind2sub(size(Dm), idx);
            a = act(ai);
            tr(a).f(end+1) = f; tr(a).x(end+1) = blobs(bi, 1); tr(a).y(end+1) = blobs(bi, 2);
            tr(a).w(end+1) = blobs(bi, 3); tr(a).a(end+1) = blobs(bi, 4);
            last_f(a) = f; last_x(a) = blobs(bi, 1); last_y(a) = blobs(bi, 2);
            used(bi) = true; Dm(ai, :) = inf; Dm(:, bi) = inf;
        end
    end
    for bi = find(~used)'
        tr(end+1) = struct('f', f, 'x', blobs(bi, 1), 'y', blobs(bi, 2), 'w', blobs(bi, 3), 'a', blobs(bi, 4)); %#ok<AGROW>
        k = numel(tr);
        last_f(k, 1) = f; last_x(k, 1) = blobs(bi, 1); last_y(k, 1) = blobs(bi, 2);
        act(end+1, 1) = k; %#ok<AGROW>
    end
end

% Re-join same-place pieces of one stance split by a brief dropout.
n = numel(tr);
t_first = arrayfun(@(k) t(tr(k).f(1)), (1:n)');
[~, ord] = sort(t_first);
alive = true(n, 1);
for ii = 1:n
    a = ord(ii);
    if ~alive(a), continue; end
    merged = true;
    while merged
        merged = false;
        ta = t(tr(a).f(end));
        xa = wmean(tr(a).x, tr(a).w); ya = wmean(tr(a).y, tr(a).w);
        for jj = ii+1:n
            b = ord(jj);
            if t_first(b) > ta + join_gap, break; end
            if ~alive(b) || t_first(b) < ta, continue; end
            if hypot(xa - wmean(tr(b).x, tr(b).w), ya - wmean(tr(b).y, tr(b).w)) <= join_px
                tr(a) = concat_track(tr(a), tr(b));
                alive(b) = false; merged = true;
                break;
            end
        end
    end
end
tr = tr(alive);

% Split at pressure valleys (fore-to-hind handoff on the same print).
parts = struct('f', {}, 'x', {}, 'y', {}, 'w', {}, 'a', {});
for k = 1:numel(tr)
    parts = [parts, split_valleys(tr(k), valley_frac)]; %#ok<AGROW>
end

contacts = struct('start_time', {}, 'end_time', {}, 'duration', {}, 'start_frame', {}, ...
    'end_frame', {}, 'centroid_x', {}, 'centroid_y', {}, 'dynamic_peak_total_pressure', {}, ...
    'valid_stance', {}, 'label', {}, 'track', {});
for k = 1:numel(parts)
    p = parts(k);
    t0 = t(p.f(1)); t1 = t(p.f(end));
    if t1 - t0 < min_dur || max(p.w) < min_peak, continue; end
    contacts(end+1, 1) = struct('start_time', t0, 'end_time', t1, 'duration', t1 - t0, ...
        'start_frame', p.f(1), 'end_frame', p.f(end), ...
        'centroid_x', wmean(p.x, p.w), 'centroid_y', wmean(p.y, p.w), ...
        'dynamic_peak_total_pressure', max(p.w), 'valid_stance', true, 'label', '', ...
        'track', struct('frame', p.f(:), 'time', t(p.f(:)), 'cx', p.x(:), 'cy', p.y(:), ...
        'total_pressure', p.w(:), 'area', p.a(:))); %#ok<AGROW>
end
if ~isempty(contacts)
    [~, o] = sort([contacts.start_time]);
    contacts = contacts(o);
end
end

function parts = split_valleys(tk, frac)
parts = tk;
w = movmean(tk.w, 3);
n = numel(w);
if n < 7 || frac >= 1, return; end
best = 0; best_ratio = inf;
for m = 3:n-2
    if w(m) > w(m-1) || w(m) > w(m+1), continue; end
    ratio = w(m) / min(max(w(1:m)), max(w(m:end)));
    if ratio < frac && ratio < best_ratio
        best = m; best_ratio = ratio;
    end
end
if best == 0, return; end
parts = [split_valleys(sub_track(tk, 1:best), frac), split_valleys(sub_track(tk, best+1:n), frac)];
end

function s = sub_track(tk, idx)
s = struct('f', tk.f(idx), 'x', tk.x(idx), 'y', tk.y(idx), 'w', tk.w(idx), 'a', tk.a(idx));
end

function a = concat_track(a, b)
a.f = [a.f b.f]; a.x = [a.x b.x]; a.y = [a.y b.y]; a.w = [a.w b.w]; a.a = [a.a b.a];
end

function m = wmean(x, w)
m = sum(x .* w) / sum(w);
end

function value = get_opt(opts, name, default_value)
if isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name))
    value = opts.(name);
else
    value = default_value;
end
end

function [events_out, info] = assign_mobile_paw_labels(events, frames, times, opts)
if nargin < 4 || isempty(opts), opts = struct(); end
s_along = get_opt(opts, 's_along', 5);
s_lat = get_opt(opts, 's_lat', 3);
along_win = get_opt(opts, 'along_win', 0.3);
lat_win = get_opt(opts, 'lat_win', 0.6);
head_win = get_opt(opts, 'head_win', 1.5);
w_votes = get_opt(opts, 'w_votes', 0.3);
dup_px = get_opt(opts, 'dup_px', 5);
cand_min_dur = get_opt(opts, 'cand_min_dur', 0.15);
cand_min_peak = get_opt(opts, 'cand_min_peak', 4e4);
overlap_s = get_opt(opts, 'overlap_s', 0.02);
overlap_pen = get_opt(opts, 'overlap_pen', log(0.01));
lr_sign = get_opt(opts, 'lr_sign', 1);
thresh = get_opt(opts, 'pressure_thresh', 200);
P4 = ["FL", "FR", "HL", "HR"];

t = double(times(:));
W = get_opt(opts, 'bout_windows', []);
if isempty(W)
    [t_ds, is_moving] = mobile_bout_mask(frames, times);
    W = mask_to_windows(t_ds, is_moving);
end

% Whole-board COP at full rate.
nf = size(frames, 3);
[XX, YY] = meshgrid(1:size(frames, 2), 1:size(frames, 1));
copx = nan(nf, 1); copy = nan(nf, 1);
for f = 1:nf
    fr = double(frames(:, :, f));
    m = fr > thresh;
    if ~any(m(:)), continue; end
    w = fr(m); s = sum(w);
    copx(f) = sum(XX(m) .* w) / s;
    copy(f) = sum(YY(m) .* w) / s;
end
ok = ~isnan(copx);
fs = 1 / median(diff(t));
if nnz(ok) >= 2
    copx = interp1(t(ok), copx(ok), t, 'linear', 'extrap');
    copy = interp1(t(ok), copy(ok), t, 'linear', 'extrap');
end
sx = movmean(copx, max(1, round(along_win * fs)));
sy = movmean(copy, max(1, round(along_win * fs)));
sxl = movmean(copx, max(1, round(lat_win * fs)));
syl = movmean(copy, max(1, round(lat_win * fs)));

n = numel(events);
valid = arrayfun(@(e) logical(get_field(e, 'valid_stance', false)), events(:));
t0 = arrayfun(@(e) double(get_field(e, 'start_time', NaN)), events(:));
t1 = arrayfun(@(e) double(get_field(e, 'end_time', NaN)), events(:));
ex = arrayfun(@(e) double(get_field(e, 'centroid_x', NaN)), events(:));
ey = arrayfun(@(e) double(get_field(e, 'centroid_y', NaN)), events(:));
peak = arrayfun(@(e) double(get_field(e, 'dynamic_peak_total_pressure', 0)), events(:));
qv = zeros(n, 4);
for k = 1:n
    v = double(get_field(events(k), 'quad_votes', zeros(1, 4)));
    v = v(:)'; v(end+1:4) = 0; qv(k, :) = v(1:4);
end
mid = 0.5 * (t0 + t1);
cand = valid | (t1 - t0 >= cand_min_dur & peak >= cand_min_peak);

in_bout = false(n, 1);
lab = strings(n, 1); src = strings(n, 1); margin = nan(n, 1); dup = false(n, 1);
for k = find(valid)'
    lab(k) = string(get_field(events(k), 'label', "")); src(k) = "detector";
end
n_bouts_used = 0;
for b = 1:size(W, 1)
    bi = find(t >= W(b, 1) & t <= W(b, 2));
    kb = mid >= W(b, 1) & mid <= W(b, 2);
    in_bout(kb) = true;
    lab(kb) = ""; src(kb) = "";
    if numel(bi) < 6, continue; end
    dirb = sign(mean(sx(bi(end-2:end))) - mean(sx(bi(1:3))));
    k = find(cand & kb);
    if dirb == 0 || isempty(k), continue; end
    n_bouts_used = n_bouts_used + 1;

    f = interp1(t, (1:numel(t))', mid(k), 'nearest', 'extrap');
    hx = dirb * ones(numel(k), 1); hy = zeros(numel(k), 1);
    if head_win > 0
        hw = round(head_win * fs / 2);
        fa = max(1, f - hw); fb = min(numel(t), f + hw);
        dx = sx(fb) - sx(fa); dy = sy(fb) - sy(fa); nr = hypot(dx, dy);
        good = nr > 3 & sign(dx) == dirb;
        hx(good) = dx(good) ./ nr(good); hy(good) = dy(good) ./ nr(good);
    end
    along = (ex(k) - sx(f)) .* hx + (ey(k) - sy(f)) .* hy;
    lat = ((ex(k) - sxl(f)) .* (-hy) + (ey(k) - syl(f)) .* hx) * lr_sign;

    lf = -log1p(exp(-along / s_along)); lh = -log1p(exp(along / s_along));
    lr = -log1p(exp(-lat / s_lat)); ll = -log1p(exp(lat / s_lat));
    E = [lf + ll, lf + lr, lh + ll, lh + lr];
    E = E + w_votes * log((qv(k, :) + 1) ./ (sum(qv(k, :), 2) + 4));

    % merge overlapping fragments of one print into a unit
    unit = (1:numel(k))';
    for a = 1:numel(k)
        for c = a+1:numel(k)
            ov = min(t1(k(a)), t1(k(c))) - max(t0(k(a)), t0(k(c)));
            if ov > 0 && hypot(ex(k(a)) - ex(k(c)), ey(k(a)) - ey(k(c))) < dup_px
                unit(unit == unit(c)) = unit(a);
            end
        end
    end
    [~, ~, ui] = unique(unit);
    nu = max(ui);
    EU = zeros(nu, 4);
    for j = 1:nu, EU(j, :) = sum(E(ui == j, :), 1); end
    ut0 = accumarray(ui, t0(k), [], @min);
    ut1 = accumarray(ui, t1(k), [], @max);

    fore_ll = logsumexp2(EU(:, 1), EU(:, 2)); hind_ll = logsumexp2(EU(:, 3), EU(:, 4));
    gird = 1 + (hind_ll > fore_ll);
    side = zeros(nu, 1); side_m = zeros(nu, 1);
    for g = 1:2
        idx = find(gird == g);
        [~, o2] = sort(ut0(idx)); idx = idx(o2);
        m = numel(idx);
        if m == 0, continue; end
        em = EU(idx, 2*g-1:2*g);
        D = zeros(m, 2); B = ones(m, 2); D(1, :) = em(1, :);
        for q = 2:m
            ov = min(ut1(idx(q)), ut1(idx(q-1))) - max(ut0(idx(q)), ut0(idx(q-1)));
            T = zeros(2);
            if ov > overlap_s, T = [overlap_pen 0; 0 overlap_pen]; end
            for s = 1:2
                [D(q, s), B(q, s)] = max(D(q-1, :)' + T(:, s));
                D(q, s) = D(q, s) + em(q, s);
            end
        end
        path = zeros(m, 1); [~, path(m)] = max(D(m, :));
        for q = m-1:-1:1, path(q) = B(q+1, path(q+1)); end
        side(idx) = path;
        side_m(idx) = abs(em(:, 2) - em(:, 1));
    end
    ulab = P4(2 * (gird - 1) + side);
    um = min(abs(hind_ll - fore_ll), side_m);
    lab(k) = ulab(ui);
    margin(k) = um(ui);
    src(k) = "mobile_assign";
    src(k(~valid(k))) = "mobile_assign_promoted";
    for j = 1:nu
        mem = k(ui == j);
        if numel(mem) > 1
            [~, keep] = max(t1(mem) - t0(mem));
            dup(mem([1:keep-1, keep+1:end])) = true;
        end
    end
end

events_out = events;
for k = 1:n
    events_out(k).mobile_in_bout = in_bout(k);
    events_out(k).mobile_label = char(lab(k));
    events_out(k).mobile_label_source = char(src(k));
    events_out(k).mobile_margin = margin(k);
    events_out(k).mobile_duplicate = dup(k);
    events_out(k).mobile_valid = strlength(lab(k)) > 0 && ~dup(k);
end
assigned = src == "mobile_assign" | src == "mobile_assign_promoted";
info = struct('n_bouts', size(W, 1), 'n_bouts_used', n_bouts_used, ...
    'bout_windows', W, 'n_assigned', nnz(assigned), ...
    'n_promoted', nnz(src == "mobile_assign_promoted"), ...
    'n_changed_from_detector', nnz(assigned & valid & lab ~= arrayfun(@(e) string(get_field(e, 'label', "")), events(:))), ...
    'n_duplicates', nnz(dup));
end

function W = mask_to_windows(t, m)
m = logical(m(:)); 
t = t(:);
d = diff([false; m; false]);
s = find(d == 1); 
e = find(d == -1) - 1;
W = [t(s), t(e)];
end

function z = logsumexp2(a, b)
mx = max(a, b); 
z = mx + log(exp(a - mx) + exp(b - mx));
end

function value = get_field(s, name, default_value)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = default_value;
end
end

function [t_ds, is_moving] = mobile_bout_mask(frames, time)

S.PRESSURE_THRES = 700;
S.MIN_TOTAL_PRESSURE = S.PRESSURE_THRES * 150;
S.TARGET_FS = 100;
S.MEDFILT_WIN = 10;
S.LOWPASS_HZ = 3.0;
S.VEL_WINDOW_SEC = 3.0;
S.STAT_QUANTILE = 0.35;
S.UP_QUANTILE = 0.60;
S.MIN_CONSEC_SEC = 0.05;
S.MIN_DUR_SEC = 0.30;
S.IGNORE_FIRST_SEC = 5.0;

time = double(time(:));
dt = median(diff(time), 'omitnan');
fs_orig = 1 / dt;
ds_factor = max(1, round(fs_orig / S.TARGET_FS));
idx_ds = 1:ds_factor:numel(time);
t_ds = time(idx_ds);
fs_ds = fs_orig / ds_factor;
n = numel(idx_ds);

cop_x = nan(n,1); cop_y = nan(n,1); total_pressure = zeros(n,1);
for k = 1:n
    frame = double(frames(:,:,idx_ds(k)));
    mask = frame > S.PRESSURE_THRES;
    if ~any(mask(:)), continue; end
    [yy, xx] = find(mask); w = frame(mask);
    sw = sum(w, 'omitnan');
    if sw <= 0, continue; end
    cop_x(k) = sum(double(xx).*w) / sw;
    cop_y(k) = sum(double(yy).*w) / sw;
    total_pressure(k) = sw;
end

ok = ~isnan(cop_x) & ~isnan(cop_y);
if sum(ok) > S.MEDFILT_WIN
    xi = (1:n)';
    cop_x(~ok) = interp1(xi(ok), cop_x(ok), xi(~ok), 'nearest', 'extrap');
    cop_y(~ok) = interp1(xi(ok), cop_y(ok), xi(~ok), 'nearest', 'extrap');
    cop_x = medfilt1(cop_x, S.MEDFILT_WIN);
    cop_y = medfilt1(cop_y, S.MEDFILT_WIN);
    if S.LOWPASS_HZ < fs_ds / 2
        [b, a] = butter(4, S.LOWPASS_HZ / (fs_ds / 2), 'low');
        cop_x = filtfilt(b, a, cop_x);
        cop_y = filtfilt(b, a, cop_y);
    end
end

velocity = zeros(n,1);
vel_step = max(1, round(S.VEL_WINDOW_SEC * fs_ds / 2));
for i = vel_step+1:n-vel_step
    dtt = t_ds(i+vel_step) - t_ds(i-vel_step);
    if dtt > 0
        velocity(i) = hypot(cop_x(i+vel_step)-cop_x(i-vel_step), cop_y(i+vel_step)-cop_y(i-vel_step)) / dtt;
    end
end
speed = movmean(abs(velocity), max(3, round(0.10 * fs_ds)), 'omitnan');
nz = speed(speed > 0 & ~isnan(speed));
if isempty(nz)
    is_moving = false(n,1);
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
is_moving_raw(t_ds(:) - t_ds(1) < S.IGNORE_FIRST_SEC) = false;
min_consec = max(1, round(S.MIN_CONSEC_SEC * fs_ds));
min_dur = max(1, round(S.MIN_DUR_SEC * fs_ds));
raw = medfilt1(double(is_moving_raw), 5) > 0.5;
raw = movsum(double(raw), [min_consec-1 0]) >= min_consec;
is_moving = bwareaopen(logical(raw), min_dur);
end
