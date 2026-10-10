function [grams, in_range, board] = s5_calibrate_to_grams(pixel_sum, where)
% Pixel sum -> grams with the board's PCHIP curve (data/calibration_0_450);
% where = centroid_x (px) or a board name. Above the fitted range -> NaN.

persistent cal
if isempty(cal)
    cfg = gait_config();
    cal = jsondecode(fileread(cfg.calibration_json));
end
if ischar(where) || isstring(where)
    board = char(where);
else
    board = board_for_x(where);
end
grams = nan(size(pixel_sum)); in_range = false(size(pixel_sum));
if isempty(board), return; end
if ~isfield(cal.boards, board)
    error('s5_calibrate_to_grams:unknownBoard', 'Unknown board "%s" (board1..board4).', board);
end
x = double(cal.boards.(board).pixel_sum_knots(:));
y = double(cal.boards.(board).force_g_knots(:));
v = double(pixel_sum);
in_range = v >= x(1) & v <= x(end);
grams(v < x(1)) = 0;
if any(in_range(:)), grams(in_range) = pchip(x, y, v(in_range)); end
end

function board = board_for_x(centroid_x)
board = '';
if isempty(centroid_x) || isnan(centroid_x), return; end
layout_board_ids = [4 3 2 1];
col = min(4, max(1, floor((double(centroid_x) - 1) / 64) + 1));
board = sprintf('board%d', layout_board_ids(col));
end
