function A = load_signal(fname, N_sensor)
% LOAD_SIGNAL  Load a T x N_sensor acceleration matrix, dropping a leading
%              time column when present. Handles both:
%                .xlsx : numeric matrix (may or may not have a time column)
%                .xls  : DSC export with header rows + a time column
    if ~isfile(fname)
        error('File not found: %s (put it in the current folder).', fname);
    end
    [~,~,ext] = fileparts(fname);
    if strcmpi(ext,'.xls')
        raw = readmatrix(fname);                 % header rows -> NaN
        raw = raw(all(~isnan(raw),2), :);        % keep fully-numeric rows
        A   = raw(:, 2:1+N_sensor);              % col 1 = time, next = channels
    else
        A = readmatrix(fname);
        if size(A,2) == N_sensor + 1             % leading time column present
            A = A(:, 2:1+N_sensor);
        else
            A = A(:, 1:N_sensor);
        end
    end
end
