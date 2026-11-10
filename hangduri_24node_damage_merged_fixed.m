%% hangduri_24node_damage_merged_fixed.m   [수정본: 손상 상태 상태공간 계산]
% ========================================================================
% 원본(hangduri_24node_damage_merged.m) 대비 변경점:
%   (1) 손상 M,K를 raw로 상태공간에 넣지 않는다.
%       무손상 Updating 연산자(scaleOpt)를 손상 FE에 동일 적용해
%       손상 디지털 트윈(Md_tw, Kd_tw)을 구성한다. -> baseline과 같은 보정 기준.
%   (2) 감쇠는 손상 진동수로 재계산하지 않고, 무손상 보정 Rayleigh 계수
%       (alphaUp, betaUp)를 동결해 Cd = alphaUp*Md_tw + betaUp*Kd_tw.
%   baseline은 원본처럼 무손상 업데이트 트윈 Mup,Kup,Cup 사용.
% ========================================================================

% clear; clc; close all;

%% 1. USER SETTINGS
doSimulation = true;
nNode = 24;  nStation = 12;
pairFE = [(1:12)', (13:24)'];
groupStation = {1:3, 4:6, 7:9, 10:12};   % 무손상 코드와 동일
deck_width = 20.0;

% 손상 M,K 파일 (NX-Nastran 케이블4개 파단, 24x24)
M_dmg_candidates = { 'haduri_node24_M_matrix_Damage_unit_kg_.xlsx', ...
                     'haduri_node24_M matrix_Damage(unit kg).xlsx'};
K_dmg_candidates = { 'haduri_node24_K_matrix_Damage_unit_N_per_m_.xlsx', ...
                     'haduri_node24_K matrix_Damage(unit N per m).xlsx'};

mergedResultFile = 'hangduri_24node_merged_result.mat';

% 상태공간 응답 시뮬레이션 입력 (무손상과 동일)
inputType = 'step';  force_node_example = 10;  force_N_example = -1000.0;
sineFreqHz = 0.45;  dt = 0.01;  tEnd = 20.0;
outPrefix = 'hangduri_24node_damage';

%% 2. 손상 FE M,K 로드 + 무손상 연산자/감쇠 로드 -> 손상 트윈 구성
fprintf('1) Read damaged FE M,K and build damaged twin\n');
M_dmg_file = find_existing_file(M_dmg_candidates, true);
K_dmg_file = find_existing_file(K_dmg_candidates, true);
Md_FE = read_numeric_square_from_excel(M_dmg_file, nNode);
Kd_FE = read_numeric_square_from_excel(K_dmg_file, nNode);
[Md_FE, Kd_FE] = clean_and_check_MK(Md_FE, Kd_FE);

if exist(mergedResultFile,'file') ~= 2
    error('baseline 결과 파일 필요: %s', mergedResultFile);
end
S = load(mergedResultFile, 'Mup','Kup','Cup','scaleOpt','alphaUp','betaUp');
M0 = S.Mup;  K0 = S.Kup;  C0 = S.Cup;     % baseline = 무손상 업데이트 트윈
scaleOpt = S.scaleOpt(:);
alphaUp  = S.alphaUp;  betaUp = S.betaUp;

% 무손상과 동일한 파라메트릭 연산자 적용
T = build_center_torsion_transform(pairFE, nNode);
Tinv = inv(T);
[Md, Kd] = apply_group_center_torsion_scaling(Md_FE, Kd_FE, T, Tinv, groupStation, scaleOpt);
[Md, Kd] = clean_and_check_MK(Md, Kd);

fprintf('  raw   ||Kd_FE - Kup||/||Kup|| = %.2f %% (사용안함)\n', norm(Kd_FE-K0,'fro')/norm(K0,'fro')*100);
fprintf('  twin  ||Kd_twin - Kup||/||Kup|| = %.2f %% (순수 손상)\n', norm(Kd-K0,'fro')/norm(K0,'fro')*100);

%% 3. MODAL ANALYSIS (검증용)
[freqDmg, ~] = modal_analysis_MK(Md, Kd, 12);
[freq0,   ~] = modal_analysis_MK(M0, K0, 12);
fprintf('Baseline f(1~5) [Hz]: '); fprintf('%.4f ', freq0(1:5)); fprintf('\n');
fprintf('Damaged  f(1~5) [Hz]: '); fprintf('%.4f ', freqDmg(1:5)); fprintf('\n');

%% 4. DAMPING (동결) + STATE-SPACE
Cd = alphaUp*Md + betaUp*Kd;  Cd = 0.5*(Cd+Cd.');   % 감쇠 동결
[Ad, Bd, CdispD, Dd] = build_state_space(Md, Cd, Kd);
[A0, B0, Cdisp0, D0] = build_state_space(M0, C0, K0);

%% 5. STATE-SPACE RESPONSE SIMULATION
if doSimulation
    t = (0:dt:tEnd).';
    u = zeros(length(t), nNode);
    switch lower(inputType)
        case 'step',          u(:,force_node_example) = force_N_example;
        case 'impulse_approx',u(1,force_node_example) = force_N_example/dt;
        case 'sine',          u(:,force_node_example) = force_N_example*sin(2*pi*sineFreqHz*t);
        otherwise, error('Unknown inputType: %s', inputType);
    end
    yd = lsim(ss(Ad,Bd,CdispD,Dd), u, t);
    y0 = lsim(ss(A0,B0,Cdisp0,D0), u, t);
    [centerD, torsionD] = compute_center_torsion_response(yd, pairFE, deck_width);
    [center0, torsion0] = compute_center_torsion_response(y0, pairFE, deck_width);
else
    t=[];u=[];yd=[];y0=[];centerD=[];torsionD=[];center0=[];torsion0=[];
end

%% 6. SAVE
save([outPrefix '_result.mat'], ...
    'Md','Kd','Cd','Ad','Bd','CdispD','Dd', ...
    'M0','K0','C0','A0','B0','Cdisp0','D0', ...
    'Md_FE','Kd_FE','scaleOpt','alphaUp','betaUp', ...
    'pairFE','deck_width','dt','tEnd','inputType','doSimulation', ...
    't','u','yd','centerD','torsionD','y0','center0','torsion0','freqDmg','freq0');
fprintf('\nSaved: %s_result.mat\n', outPrefix);
fprintf('Done. 다음: run_seismic_simulation_damage_fixed.m 로 가속도 응답 추출\n');

%% 모든 열린 figure를 .fig로 자동 저장 (PNG는 저장하지 않음)
save_all_figs_as_fig();

%% ---- 다음 실행 안내 (파이프라인 2/9 완료) ----
fprintf('\n================ 다음 실행 스크립트 ================\n');
fprintf('  [2/9] 상태공간 변위 응답 검증 완료 (그림 3·4)\n');
fprintf('  >> 다음 실행: run_seismic_simulation_from_merged.m\n');
fprintf('     (무손상 지진응답 생성 — 그림 5·6, hangduri_24node_seismic_accel.xlsx)\n');
fprintf('====================================================\n');

%% ===== LOCAL FUNCTIONS =====
function filename = find_existing_file(candidates, required)
    filename = '';
    for i = 1:length(candidates)
        if exist(candidates{i}, 'file') == 2, filename = candidates{i}; return; end
    end
    if required, error('Required file not found: %s', strjoin(candidates, ', ')); end
end

function X = read_numeric_square_from_excel(filename, n)
    raw = readmatrix(filename);
    raw = raw(~all(isnan(raw),2), :);  raw = raw(:, ~all(isnan(raw),1));
    if size(raw,1) == n && size(raw,2) == n
        X = raw;
    elseif size(raw,1) >= n && size(raw,2) >= n
        X = raw(end-n+1:end, end-n+1:end);
    else
        error('Cannot extract %d x %d matrix from %s.', n, n, filename);
    end
    X = double(X);  X(~isfinite(X)) = 0;
end

function [M, K] = clean_and_check_MK(M, K)
    M = 0.5*(M + M.');  K = 0.5*(K + K.');
    if any(~isfinite(M(:))) || any(~isfinite(K(:))), error('M or K contains NaN/Inf.'); end
end

function [freqHz, Phi] = modal_analysis_MK(M, K, nMode)
    [V,D] = eig(K, M);
    lam = real(diag(D));  valid = lam > 0 & isfinite(lam);
    lam = lam(valid);  V = real(V(:,valid));
    freq = sqrt(lam)/(2*pi);  [freqHz, idx] = sort(freq, 'ascend');
    Phi = V(:,idx);  nMode = min(nMode, length(freqHz));
    freqHz = freqHz(1:nMode);  Phi = Phi(:,1:nMode);
end

function T = build_center_torsion_transform(pairFE, nNode)
    nPair = size(pairFE,1);  T = zeros(nNode,nNode);
    for i = 1:nPair
        L = pairFE(i,1); R = pairFE(i,2);
        T(i,L) = 0.5;  T(i,R) = 0.5;
    end
    for i = 1:nPair
        L = pairFE(i,1); R = pairFE(i,2);
        T(nPair+i,L) = 0.5;  T(nPair+i,R) = -0.5;
    end
end

function [Mnew, Knew] = apply_group_center_torsion_scaling(M, K, T, Tinv, groupStation, scale)
    n = size(M,1); nHalf = n/2; nGroup = numel(groupStation);
    if length(scale) ~= 2*nGroup + 2, error('scale length must be %d.', 2*nGroup + 2); end
    Kq = Tinv' * K * Tinv;  Mq = Tinv' * M * Tinv;
    Dk = eye(n); Dm = eye(n);
    for g = 1:nGroup, idx = groupStation{g};         Dk(idx,idx) = sqrt(scale(g))*eye(length(idx)); end
    for g = 1:nGroup, idx = nHalf + groupStation{g}; Dk(idx,idx) = sqrt(scale(nGroup+g))*eye(length(idx)); end
    Dm(1:nHalf,1:nHalf)         = sqrt(scale(2*nGroup+1))*eye(nHalf);
    Dm(nHalf+1:end,nHalf+1:end) = sqrt(scale(2*nGroup+2))*eye(nHalf);
    Knew = T' * (Dk * Kq * Dk) * T;  Mnew = T' * (Dm * Mq * Dm) * T;
    Knew = 0.5*(Knew + Knew');  Mnew = 0.5*(Mnew + Mnew');
end

function [A, B, Cout, D] = build_state_space(M, C, K)
    n = size(M,1);  Z = zeros(n);  I = eye(n);
    A = [Z, I; -(M\K), -(M\C)];  B = [Z; M\eye(n)];  Cout = [I, Z];  D = zeros(n,n);
end

function [centerResp, torsionResp] = compute_center_torsion_response(y, pairFE, deck_width)
    nT = size(y,1);  nPair = size(pairFE,1);
    centerResp = zeros(nT,nPair);  torsionResp = zeros(nT,nPair);
    for i = 1:nPair
        L = pairFE(i,1);  R = pairFE(i,2);
        wL = y(:,L);  wR = y(:,R);
        centerResp(:,i)  = 0.5*(wL + wR);
        torsionResp(:,i) = (wL - wR)/deck_width;
    end
end
