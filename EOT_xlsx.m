% =====================================================================================
% Program : EOT_xlsx.m   (Energy Optimal Technique, run-once driver)
% Based on the original EOT.m (written by Heo since 1996).
%
% Reads FE data from Excel, runs the EOT core (eot_select.m), and plots the
% KE-determinant (information) curve versus number of removed sensors.
%
%     FE_Mass_matrix.xlsx   -> N x N mass matrix
%     FE_Eigen_Vector.xlsx  -> first column = node id, remaining = mode shapes
%
% This driver calls eot_select.m instead of duplicating the algorithm, so the
% run-once view and the analysis/performance drivers all share ONE core.
%
% [REVISION] mode_idx를 mode_selection_basis.m의 결과(mode_selection_result.mat,
% recommendedModes)로부터 자동으로 불러오도록 연동함.
%   - useAutoModeSelection = true  : mode_selection_result.mat에서 자동 로드 (기본)
%   - useAutoModeSelection = false : mode_idx_manual을 그대로 사용 (기존 방식)
% 전제: FE_Eigen_Vector.xlsx의 모드 열 순서가 mode_selection_basis.m의
%       mode_freq 순서와 동일해야 함. 처음 실행 시 반드시 대조 확인할 것.
%
% [F5 실행 안정화]
%   - cd 경로가 없어도 멈추지 않도록 안전 처리 (경로 있으면 이동, 없으면 현재폴더 사용)
%   - 필수 함수/파일 존재 여부를 먼저 점검해 친절한 오류 메시지 제공
% =====================================================================================

% clear; clc; close all;

% ---------------------------------------------------------------------------
% 0. USER SETTINGS
% ---------------------------------------------------------------------------
% 작업 폴더: 존재하면 이동, 없으면 현재 폴더에서 그대로 진행 (F5 실행이 멈추지 않도록)
workDir = 'F:\기존자료\건양대학교\공공안전연구소\업무\논문\IMD\SCI\새 폴더';
if isfolder(workDir)
    cd(workDir);
    fprintf('작업 폴더로 이동: %s\n', workDir);
else
    fprintf('지정한 작업 폴더가 없어 현재 폴더에서 실행합니다: %s\n', pwd);
end

mass_file      = 'haduri_node24_M matrix(unit kg).xlsx';
evec_file      = 'handuri_24node_Eigen_Vector.xlsx';

useAutoModeSelection = true;      % true: mode_selection_result.mat에서 자동 로드
modeSelFile          = 'mode_selection_result.mat';

mode_idx_manual = [1 4 5 6 7 8 9 10];    %! useAutoModeSelection=false일 때만 사용되는 수동 지정값
opt_no_sensor   = 8;              %! 선정 센서 수(= IMD에서 쓰는 8개, no_mode와 일치)

% ---------------------------------------------------------------------------
% 0b. 의존성 점검 (F5 실행 전 필수 파일/함수 확인)
% ---------------------------------------------------------------------------
if exist('eot_select', 'file') ~= 2
    error('EOT_xlsx:missingCore', ...
        ['EOT 코어 함수 eot_select.m을 찾을 수 없습니다. ', ...
         '이 파일이 현재 폴더나 MATLAB 경로에 있는지 확인하세요.']);
end
if exist(mass_file, 'file') ~= 2
    error('EOT_xlsx:missingMass', ...
        '질량행렬 파일을 찾을 수 없습니다: %s (현재 폴더: %s)', mass_file, pwd);
end
if exist(evec_file, 'file') ~= 2
    error('EOT_xlsx:missingEvec', ...
        '고유벡터 파일을 찾을 수 없습니다: %s (현재 폴더: %s)', evec_file, pwd);
end

% ---------------------------------------------------------------------------
% 0c. mode_idx 결정 (자동 로드 또는 수동 지정)
% ---------------------------------------------------------------------------
if useAutoModeSelection
    if exist('load_recommended_modes', 'file') ~= 2
        error('EOT_xlsx:missingLoader', ...
            ['load_recommended_modes.m을 찾을 수 없습니다. ', ...
             '이 파일을 경로에 두거나 useAutoModeSelection=false로 바꿔 수동 지정을 사용하세요.']);
    end
    if exist(modeSelFile, 'file') ~= 2
        error('EOT_xlsx:missingModeSel', ...
            ['%s를 찾을 수 없습니다. mode_selection_basis.m을 먼저 실행하거나, ', ...
             'useAutoModeSelection=false로 바꿔 수동 지정을 사용하세요.'], modeSelFile);
    end
    [mode_idx, targetModeFreq, no_mode_auto] = load_recommended_modes(modeSelFile);
    fprintf('[EOT_xlsx] target mode 자동 로드 (%s): %s (%d개, %.3f~%.3f Hz)\n', ...
        modeSelFile, mat2str(mode_idx), no_mode_auto, min(targetModeFreq), max(targetModeFreq));
else
    mode_idx = mode_idx_manual;
    fprintf('[EOT_xlsx] mode_idx 수동 지정 사용: %s\n', mat2str(mode_idx));
end

% ---------------------------------------------------------------------------
% 1. READ DATA
% ---------------------------------------------------------------------------
Mass_Matrix = readmatrix(mass_file);      % N x N
EVR_raw     = readmatrix(evec_file);      % N x (1 + modes)
node_id     = EVR_raw(:, 1);              % first column = real node numbers
EVR         = EVR_raw(:, 2:end);          % remaining = mode shapes
N           = size(Mass_Matrix,1);
no_mode     = numel(mode_idx);

% ---------------------------------------------------------------------------
% 2. VALIDATION
% ---------------------------------------------------------------------------
fprintf('--- Input validation ---\n');
fprintf('Mass matrix size      : %d x %d\n', size(Mass_Matrix,1), size(Mass_Matrix,2));
fprintf('Eigenvector size      : %d x %d\n', size(EVR,1), size(EVR,2));
fprintf('Mass symmetry error   : %.3e\n', norm(Mass_Matrix - Mass_Matrix'));
fprintf('Mass rank / N         : %d / %d\n', rank(Mass_Matrix), N);
fprintf('Mass condition number : %.3e\n', cond(Mass_Matrix));

if size(Mass_Matrix,1) ~= size(Mass_Matrix,2)
    error('Mass matrix is not square.');
end
if size(EVR,1) ~= N
    error('Row count of eigenvectors (%d) does not match mass matrix size (%d).', size(EVR,1), N);
end
if max(mode_idx) > size(EVR,2)
    error('mode_idx max (%d) exceeds available modes in file (%d).', max(mode_idx), size(EVR,2));
end
if opt_no_sensor >= N
    error('opt_no_sensor (%d) must be smaller than total DOF N (%d).', opt_no_sensor, N);
end
if opt_no_sensor < no_mode
    warning('opt_no_sensor (%d) < no_mode (%d): fewer sensors than modes can cause rank deficiency.', ...
             opt_no_sensor, no_mode);
end

% ---------------------------------------------------------------------------
% 3. RUN EOT CORE
% ---------------------------------------------------------------------------
% (i) 센서 선정: opt_no_sensor개(=8) 남긴 결과 -> sel (Best Candidate, IMD에서 사용)
[sel, ~, ~] = eot_select(Mass_Matrix, EVR, mode_idx, opt_no_sensor, node_id);

% (ii) 정보곡선: rank-floor(센서수<모드수)까지 '전체' 곡선을 위해 낮은 목표(1)로 재호출.
%      opt_no_sensor=8로 두면 곡선이 9에서 끊겨 8·7이 없어 빨간 표시가 안 나오므로,
%      곡선 계산과 센서 선정을 분리한다. (KK/센서수 이력은 이 호출에서 가져옴)
[~, KK, n_remain] = eot_select(Mass_Matrix, EVR, mode_idx, 1, node_id);

retained = n_remain(:);              % 유지 센서 수 이력: 24, 23, ..., 7
xt = min(retained):max(retained);    % x눈금: 7 ~ 24 모든 정수(1씩) — 보고서 그림 11과 동일

% ---------------------------------------------------------------------------
% 4. PLOT: EOT 정보곡선 (보고서 그림 11 형태) — 두 버전 생성
%     (1) 그래프 안 빨간 글자(주석) 없는 버전
%     (2) 빨간 글자(8 sensors..., rank-deficient...) 있는 버전
%   둘 다 유지센서 24->7 축, 눈금 1씩. 아래 save_all_figs_as_fig()로 .fig 저장.
% ---------------------------------------------------------------------------
plot_eot_information_curve(retained, KK, no_mode, opt_no_sensor, xt, false);   % (1) 주석 없음
plot_eot_information_curve(retained, KK, no_mode, opt_no_sensor, xt, true);    % (2) 주석 있음

% ---------------------------------------------------------------------------
% 5. OUTPUT
% ---------------------------------------------------------------------------
fid = fopen('ke_eot.dat', 'w');
fprintf(fid, '%12.5f \n', KK);
fclose(fid);

fprintf('\n  Best Candidate Sensor Location (nodes)\n\n ');
fprintf('  %d  ', sel);
fprintf('\n\n');

%% 모든 열린 figure를 .fig로 자동 저장 (PNG는 저장하지 않음)
save_all_figs_as_fig();

%% ---- 다음 실행 안내 (파이프라인 6/9 완료) ----
fprintf('\n================ 다음 실행 스크립트 ================\n');
fprintf('  [6/9] EOT 센서 선정 완료 (그림 11)\n');
fprintf('  >> 다음 실행: run_IMD_handuri_fixed.m\n');
fprintf('     (IMD 손상 판정 — 그림 15, 관리차트 EOT vs Full)\n');
fprintf('====================================================\n');

% ===========================================================================
% LOCAL FUNCTION: EOT 정보곡선 1장 그리기 (showAnnot=true면 빨간 글자/음영 포함)
% ===========================================================================
function plot_eot_information_curve(retained, KK, no_mode, opt_sel, xt, showAnnot)
    cLine = [0.12 0.47 0.70];        % 보고서 그림 11의 파란색(순수 'b'가 아님)
    figure('Color','w','Position',[100 100 780 470]);
    hold on;
    yl = [-0.03, max(KK)*1.05];      % 그림 11과 동일: 0 아래 약간 여유 ~ 1.03

    % (주석 버전만) rank-deficient 음영: 센서 수 < 모드 수 -> det->0
    if showAnnot
        xRankL = min(retained) - 0.5;
        xRankR = no_mode      - 0.5;
        patch([xRankL xRankR xRankR xRankL], [yl(1) yl(1) yl(2) yl(2)], ...
              [0.96 0.86 0.86], 'EdgeColor','none', 'FaceAlpha',0.7, 'HandleVisibility','off');
    end

    % 정보곡선 (두 버전 공통): 선 + 채워진 원 마커, 색은 그림 11과 동일
    plot(retained, KK, '-', 'Color', cLine, 'LineWidth', 1.8);
    plot(retained, KK, 'o', 'MarkerSize', 5, ...
        'MarkerFaceColor', cLine, 'MarkerEdgeColor', cLine);

    % (주석 버전만) 빨간 글자/표시
    if showAnnot
        % (c) 선정 센서 수(opt_sel) 위치에 마커/글자 — opt_no_sensor를 바꾸면 여기로 이동
        idxSel = find(retained == opt_sel, 1);
        if ~isempty(idxSel)
            xline(opt_sel, 'r--', 'LineWidth', 1.3);
            plot(opt_sel, KK(idxSel), 'ro', 'MarkerSize', 9, 'LineWidth', 1.5);
            text(opt_sel + 0.5, max(KK)*0.42, ...
                sprintf('%d sensors (= %d modes)\ndet(KE)=%.5f', opt_sel, no_mode, KK(idxSel)), ...
                'Color', [0.75 0.10 0.10], 'FontSize', 10, ...
                'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
        end
        % (d) rank-deficient 음영/글자 — 수학적 경계(모드 수)라 opt_sel과 무관하게 고정
        if min(retained) < no_mode
            text(no_mode - 0.6, max(KK)*0.16, ...
                sprintf('rank-deficient\n(det\\rightarrow0 at %d)', no_mode-1), ...
                'Color', [0.75 0.10 0.10], 'FontSize', 9, ...
                'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
        end
    end

    set(gca, 'XDir', 'reverse');                 % 24(왼쪽) -> 7(오른쪽)
    xlim([min(retained) - 0.5, max(retained) + 0.5]);
    ylim(yl);
    set(gca, 'XTick', xt);                        % 24~7 모든 정수(1씩)
    set(gca, 'YTick', 0:0.2:1);                   % y눈금 0.0~1.0 (0.2 간격) — 그림 11과 동일
    grid on;
    box on;                                       % 외벽선(상자) 4면 모두 표시
    set(gca, 'Layer', 'top');                     % 축선/외벽선을 음영 patch 위에 그림(짤림 방지)
    xlabel('Number of retained sensors');
    ylabel('det(KE)  (modal information)');
    title('EOT information curve (Handuri 24-node)');
    hold off;
end

% =====================================================================================
% End of file
% =====================================================================================
