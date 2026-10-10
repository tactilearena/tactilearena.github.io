function result = run_demo(data_root, work_root)
% Runs s1-s4 on the demo recording (rat 4, 24 Feb 2026) and compares the
% stance events and walking windows with demo/expected/.

setenv('GAIT_DATA_ROOT', data_root);
setenv('GAIT_WORK_ROOT', work_root);
setenv('GAIT_ANNOTATIONS_ROOT', '');
here = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(here), 'pipeline'));
[cfg, R] = gait_config();
rec = R.output_name;
fprintf('Demo recording: %s\n', rec);
times = struct();

t = tic; s1_prepare_recordings("backgrounds", rec); times.s1_backgrounds = toc(t);
t = tic; r2 = s2_detect_contacts(rec); times.s2_detect = toc(t);
if r2.status ~= "done" && r2.status ~= "skipped", error('s2 failed: %s', r2.message); end
t = tic;
s3_find_mobile_bouts("extract", rec);
s3_find_mobile_bouts("stats");
s3_find_mobile_bouts("export");
times.s3_bouts = toc(t);
t = tic; s4_label_paws(rec, struct('bouts', fullfile(cfg.cop_root, 'mobile_bout_windows.csv'))); times.s4_paws = toc(t);
t = tic; s4_label_paws(rec, struct('bouts', fullfile(cfg.cop_root, 'mobile_bout_windows.csv'), 'video', true)); times.s4_video = toc(t);

% results
out_dir = fullfile(cfg.work_root, 'demo_results');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
copyfile(fullfile(cfg.contacts_root, rec + "_paw_labels.mp4"), fullfile(out_dir, 'labeled_walking_windows.mp4'));
W = readtable(fullfile(cfg.cop_root, 'mobile_bout_windows.csv'), 'TextType', 'string', 'Delimiter', ',');
C = load(fullfile(cfg.contacts_root, rec + "_mobile_contacts.mat"), 'contacts');
c = C.contacts(arrayfun(@(e) logical(e.mobile_valid), C.contacts(:)));
K = table(string({c.label})', [c.start_time]', [c.end_time]', [c.centroid_x]', [c.centroid_y]', [c.bout_index]', ...
    'VariableNames', {'label', 'start_time', 'end_time', 'centroid_x', 'centroid_y', 'bout_index'});
writetable(W, fullfile(out_dir, 'walking_windows.csv'));
writetable(K, fullfile(out_dir, 'stance_events.csv'));

fprintf('\nWalking windows: %d (%.1f s)\n', height(W), sum(W.t_end - W.t_start));
fprintf('Stance events: %d  (FL %d, FR %d, HL %d, HR %d)\n', height(K), nnz(K.label == "FL"), ...
    nnz(K.label == "FR"), nnz(K.label == "HL"), nnz(K.label == "HR"));
f = fieldnames(times);
fprintf('Run time:'); for k = 1:numel(f), fprintf('  %s %.1f min', f{k}, times.(f{k}) / 60); end; fprintf('\n');

% compare with the expected output
exp_dir = fullfile(here, 'expected');
pass = true;
pass = compare_csv(fullfile(out_dir, 'walking_windows.csv'), fullfile(exp_dir, 'walking_windows.csv')) && pass;
pass = compare_csv(fullfile(out_dir, 'stance_events.csv'), fullfile(exp_dir, 'stance_events.csv')) && pass;
if pass, fprintf('\nDEMO PASSED: output matches demo/expected.\n'); else, fprintf('\nDEMO FAILED: see differences above.\n'); end
result = struct('passed', pass, 'times_s', times, 'windows', W, 'stance_events', K);
end

function ok = compare_csv(got_path, exp_path)
[~, name] = fileparts(got_path);
if ~isfile(exp_path)
    fprintf('  %s: no expected file (%s)\n', name, exp_path); ok = false; return;
end
G = readtable(got_path, 'TextType', 'string', 'Delimiter', ',');
E = readtable(exp_path, 'TextType', 'string', 'Delimiter', ',');
ok = isequal(G.Properties.VariableNames, E.Properties.VariableNames) && height(G) == height(E);
if ok
    for v = string(G.Properties.VariableNames)
        if isnumeric(G.(v)), ok = ok && all(abs(G.(v) - E.(v)) <= 1e-9 | (isnan(G.(v)) & isnan(E.(v))));
        else, ok = ok && all(G.(v) == E.(v)); end
    end
end
word = "DIFFERS"; if ok, word = "matches"; end
fprintf('  %s: %s (%d rows, expected %d)\n', name, word, height(G), height(E));
end
