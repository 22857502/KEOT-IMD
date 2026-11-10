function [sel, KK, n_remain, knee_remain] = eot_select(Mass_Matrix, EVR, mode_idx, opt_no_sensor, node_id)
% EOT_SELECT  Energy Optimal Technique sensor selection (reusable core).
%
%   [sel, KK, n_remain, knee_remain] = ...
%           eot_select(Mass_Matrix, EVR, mode_idx, opt_no_sensor, node_id)
%
%   INPUTS
%     Mass_Matrix   : N x N mass matrix (symmetric positive definite)
%     EVR           : N x (>=max(mode_idx)) mode-shape matrix
%                     (rows = DOF/sensor, cols = modes; NO node-id column here)
%     mode_idx      : vector of mode COLUMN indices to use, e.g. [2 3 4 5].
%                     (A scalar is also accepted and treated as 1:scalar,
%                      for backward compatibility.)
%     opt_no_sensor : number of sensors to keep at the end
%     node_id       : (optional) N x 1 real node numbers. If omitted, 1..N.
%
%   OUTPUTS
%     sel         : selected sensor node numbers (or indices if node_id omitted)
%     KK          : KE-determinant history (information curve)
%     n_remain    : remaining-sensor count at each step (same length as KK)
%     knee_remain : sensor count at the knee point (NaN if not computable)
%
%   Corrections carried over from EOT_xlsx.m:
%     - mode selection by explicit column indices (mode_idx), not 1:no_mode
%     - correct per-mode mass normalization (diagonal modal mass)
%     - Cholesky factor so KE = PSI'*PSI = PHI'*M*PHI
%     - rank-deficiency stop uses (Tdof < no_mode) || (rcond(KE) < tol),
%       NOT min(sqrt(eig)) < tol   (which stopped far too early)
%     - returns real node numbers when node_id is provided

    singular_point = 1.0e-10;

    % Backward compatibility: scalar mode_idx means "first k modes"
    if isscalar(mode_idx)
        mode_idx = 1:mode_idx;
    end
    no_mode = numel(mode_idx);

    N = size(Mass_Matrix,1);
    if nargin < 5 || isempty(node_id)
        node_id = (1:N)';
    end
    node_id = node_id(:);

    MSVector     = EVR(:, mode_idx);      % selected mode columns
    Tdof         = N;
    dof_location = node_id;

    % Per-mode mass normalization  ->  PHI'*M*PHI = I
    modalMass = diag(MSVector' * Mass_Matrix * MSVector);
    PHI       = MSVector ./ sqrt(modalMass');

    % Cholesky:  Mass_Matrix = Ums'*Ums  ->  KE = PSI'*PSI = PHI'*M*PHI
    Ums = chol(Mass_Matrix);
    PSI = Ums * PHI;

    KK = []; n_remain = [];
    while Tdof > opt_no_sensor
        KE = PSI' * PSI;
        KK(end+1,1)       = det(KE);   %#ok<AGROW>
        n_remain(end+1,1) = Tdof;      %#ok<AGROW>

        % Rank-deficiency safety stop (correct criterion)
        if Tdof < no_mode || rcond(KE) < singular_point
            break;
        end

        [~, Ske, Vke] = svd(KE);
        Lambda_hlf = sqrt(diag(Ske));

        EOT      = ( PSI * Vke * diag(1 ./ Lambda_hlf) ).^2;
        EperNode = sum(EOT, 2);
        [~, dellocat] = min(EperNode);

        keep            = true(Tdof,1);
        keep(dellocat)  = false;
        PSI             = PSI(keep,:);
        dof_location    = dof_location(keep);
        Tdof            = numel(dof_location);
    end
    sel = dof_location(:)';

    % Knee point (max distance to chord of the information curve)
    knee_remain = NaN;
    if numel(KK) > 2
        x = (0:numel(KK)-1)';  y = KK;
        x0=x(1); y0=y(1); x1=x(end); y1=y(end);
        d = abs((y1-y0).*x-(x1-x0).*y+x1*y0-y1*x0)./hypot(y1-y0,x1-x0);
        [~, ki] = max(d);
        knee_remain = n_remain(ki);
    end
end
