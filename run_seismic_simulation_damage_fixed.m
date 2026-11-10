%% run_seismic_simulation_damage_fixed.m   [수정본]
% ------------------------------------------------------------------
% 원본(run_seismic_simulation_damage.m) 대비 변경점은 딱 두 가지:
%   (1) 손상 M,K를 raw로 쓰지 않는다.
%       무손상 Updating과 "동일한 파라메트릭 연산자(scaleOpt)"를 손상 FE에
%       적용해 손상 디지털 트윈(Md,Kd)을 만든다. -> baseline과 같은 보정 기준.
%       (검증: ||Kd_twin - Kup||/||Kup|| = 0.51%  = 순수 손상.
%              현재코드의 raw 방식은 11.56%로, 그중 ~96%가 미보정 갭 오염이었음)
%   (2) 감쇠는 손상 진동수로 재계산하지 않고, 무손상 보정 Rayleigh 계수
%       (alphaUp, betaUp)를 "동결"해 Cd = alphaUp*Md + betaUp*Kd 로 만든다.
%
%   나머지(El-Centro 입력, simulate/plot/export 함수, 저장)는 원본과 100% 동일.
%   baseline은 원본처럼 무손상 업데이트 트윈 Mup,Kup,Cup 을 그대로 사용.
% ------------------------------------------------------------------

% clear; clc; close all;

%% 1. 설정
dmg_M_file = 'haduri_node24_M matrix_Damage(unit kg).xlsx';
dmg_K_file = 'haduri_node24_K matrix_Damage(unit N per m).xlsx';
mergedResultFile   = 'hangduri_24node_merged_result.mat';
useBaselineCompare = true;

nNode  = 24;
pairFE = [(1:12)', (13:24)'];
groupStation = {1:3, 4:6, 7:9, 10:12};   % 무손상 코드와 동일한 4개 station 그룹

% 입력 설정 (무손상과 동일 - IMD 비교하려면 elcentro)
inputType    = 'elcentro';
elcentroFile = 'El-centro.xlsx';
elcentroUnit = 'g';
rmsAccel     = 0.05;      % whitenoise일 때만 사용
noiseSeed    = 42;

dtTarget = 0.01;
tEnd     = [];           % [] 이면 El-Centro 전체 길이 사용
outputType = 'absolute';
outPrefix  = 'hangduri_24node_cable4break';

%% 2. 손상 FE M,K 로드 + 무손상 연산자/감쇠 로드  ->  손상 트윈 구성
if exist(dmg_M_file,'file') ~= 2 || exist(dmg_K_file,'file') ~= 2
    error('손상 M,K 엑셀을 찾을 수 없습니다:\n  %s\n  %s', dmg_M_file, dmg_K_file);
end

% (a) NX-Nastran 손상 FE (미보정, raw)
Md_FE = read_square_local(dmg_M_file, nNode);
Kd_FE = read_square_local(dmg_K_file, nNode);

% (b) 무손상 파이프라인 결과: baseline 트윈 + Updating 연산자 + 동결 감쇠계수
if ~(useBaselineCompare && exist(mergedResultFile,'file')==2)
    error('baseline(무손상) 결과 파일이 필요합니다: %s', mergedResultFile);
end
S = load(mergedResultFile, 'Mup','Kup','Cup','scaleOpt','alphaUp','betaUp');
M0 = S.Mup;  K0 = S.Kup;  C0 = S.Cup;      % baseline = 무손상 업데이트 트윈
scaleOpt = S.scaleOpt(:);
alphaUp  = S.alphaUp;  betaUp = S.betaUp;

% (c) 무손상과 "동일한" 파라메트릭 스케일 연산자를 손상 FE에 적용 -> 손상 트윈
T    = build_center_torsion_transform(pairFE, nNode);
Tinv = inv(T);
[Md, Kd] = apply_group_center_torsion_scaling(Md_FE, Kd_FE, T, Tinv, groupStation, scaleOpt);

% (d) 감쇠 동결: 무손상 보정 Rayleigh 계수 그대로 적용 (손상 진동수 재계산 금지)
Cd = alphaUp*Md + betaUp*Kd;
Cd = 0.5*(Cd + Cd.');

haveBaseline = true;
fprintf('손상 트윈 구성 완료.\n');
fprintf('  raw 방식 ||Kd_FE - Kup||/||Kup|| = %.2f %% (손상+보정갭, 사용안함)\n', ...
        norm(Kd_FE-K0,'fro')/norm(K0,'fro')*100);
fprintf('  수정 방식 ||Kd_twin - Kup||/||Kup|| = %.2f %% (순수 손상)\n', ...
        norm(Kd-K0,'fro')/norm(K0,'fro')*100);

%% 3. 입력 신호 생성  (원본과 동일)
switch lower(inputType)
    case 'elcentro'
        [t_eq, ag_raw, ~] = load_ground_motion_elcentro(elcentroFile, elcentroUnit);
        if isempty(tEnd), tEndUse = t_eq(end); else, tEndUse = min(tEnd, t_eq(end)); end
        t  = (0:dtTarget:tEndUse).';
        ag = interp1(t_eq, ag_raw, t, 'linear', 'extrap');
    case 'whitenoise'
        if isempty(tEnd), tEnd = 20.0; end
        [t, ag] = generate_white_noise_input(dtTarget, tEnd, 'RmsAccel', rmsAccel, 'Seed', noiseSeed);
    otherwise
        error('inputType은 ''elcentro'' 또는 ''whitenoise''.');
end

figure('Name','Input ground motion','Visible','on');
plot(t, ag/9.80665, 'k-'); grid on;
xlabel('Time [s]'); ylabel('Ground accel [g]');
title(sprintf('Input ground motion (%s)', inputType));
saveas(gcf, [outPrefix '_input_motion.png']);

%% 4. 시뮬레이션  (원본과 동일 함수, 손상은 트윈 Md,Kd,Cd 사용)
fprintf('\n손상 트윈(Md,Kd,Cd) 지진응답 시뮬레이션 중...\n');
resultDamage = simulate_seismic_response_24node(Md, Cd, Kd, t, ag, ...
    'OutputType', outputType, 'Label', 'Cable4Break');

if haveBaseline
    fprintf('무손상 트윈(Mup,Kup,Cup) 지진응답 시뮬레이션 중...\n');
    resultBaseline = simulate_seismic_response_24node(M0, C0, K0, t, ag, ...
        'OutputType', outputType, 'Label', 'Baseline');
end

%% 5. 플롯  (원본과 동일)
if haveBaseline, plotSet = {resultBaseline, resultDamage}; else, plotSet = {resultDamage}; end
plot_seismic_acceleration_24node(plotSet, 'PlotStyle','split_ns', 'Unit','g', ...
    'OutPrefix', outPrefix, 'ShowPeakProfile', true, 'CommonYLim', true);   % 겹침 그림도 y축 통일
plot_seismic_acceleration_24node(plotSet, 'PlotStyle','individual', 'Unit','g', ...
    'OutPrefix', outPrefix, 'ShowPeakProfile', false, 'CommonYLim', true);
drawnow; shg;

%% 6. 결과 저장  (원본과 동일 + 트윈/연산자 정보 추가)
tEndActual = t(end);
if haveBaseline
    save([outPrefix '_result.mat'], 't','ag','resultDamage','resultBaseline', ...
        'Md','Kd','Cd','M0','K0','C0','Md_FE','Kd_FE','scaleOpt','alphaUp','betaUp', ...
        'outputType','dtTarget','tEndActual','inputType');
else
    save([outPrefix '_result.mat'], 't','ag','resultDamage', ...
        'Md','Kd','Cd','Md_FE','Kd_FE','scaleOpt','alphaUp','betaUp', ...
        'outputType','dtTarget','tEndActual','inputType');
end

%% 7. 가속도 엑셀 저장  (원본과 동일)
if haveBaseline
    export_accel_to_excel({resultBaseline, resultDamage}, [outPrefix '_accel.xlsx'], ...
        'Unit','g', 'SheetNames', {'Baseline','Cable4Break'});
else
    export_accel_to_excel(resultDamage, [outPrefix '_accel.xlsx'], ...
        'Unit','g', 'SheetNames', {'Cable4Break'});
end

fprintf('\n저장 완료: %s_result.mat / _accel.xlsx / _*.png\n', outPrefix);
fprintf('Done.\n');

%% 5-2. [추가] 손상(Cable4Break) '단독' 24절점 그림 (겹침 그림은 그대로 둠)
%    별도 함수 없이, plot_seismic_acceleration_24node 를 {resultDamage} 하나만 넘겨 재사용.
%    구성: 24-in-one 격자(1) + N선(1) + S선(1) + 개별(24) = 27장. 위 겹침 27장과 합쳐 손상 54장.
%    'ShowLegend',false : 단독이라 선이 하나뿐 -> 범례 생략.
%    'CommonYLim',true  : 24개 노드 y축을 동일 대칭범위로 고정(절점 간 진폭 비교용).
%    peak 프로파일은 겹침 그림에만 두어 단독에서는 중복 생성하지 않음(ShowPeakProfile,false).
%    'LineColors' : 손상 단독 그림은 무손상(파란색)과 구분되도록 주황색으로 표시.
cDam = [0.8500 0.3250 0.0980];   % MATLAB 기본 주황(겹침 그림의 Cable4Break 색과 동일)
plot_seismic_acceleration_24node({resultDamage}, ...
    'PlotStyle', 'grid', 'Unit', 'g', 'OutPrefix', '', 'CommonYLim', true, 'ShowLegend', false, 'LineColors', cDam);
plot_seismic_acceleration_24node({resultDamage}, ...
    'PlotStyle', 'split_ns', 'Unit', 'g', 'OutPrefix', '', 'ShowPeakProfile', false, 'CommonYLim', true, 'ShowLegend', false, 'LineColors', cDam);
plot_seismic_acceleration_24node({resultDamage}, ...
    'PlotStyle', 'individual', 'Unit', 'g', 'OutPrefix', '', 'ShowPeakProfile', false, 'CommonYLim', true, 'ShowLegend', false, 'LineColors', cDam);

%% 모든 열린 figure를 .fig로 자동 저장 (PNG는 저장하지 않음)
save_all_figs_as_fig();

%% ---- 다음 실행 안내 (파이프라인 4/9 완료) ----
fprintf('\n================ 다음 실행 스크립트 ================\n');
fprintf('  [4/9] 손상 지진응답 생성 완료  ->  hangduri_24node_cable4break_accel.xlsx\n');
fprintf('  >> 다음 실행: mode_selection_basis.m\n');
fprintf('     (계측 데이터 기반 모드 선정 — 그림 8·9·10, mode_selection_result.mat)\n');
fprintf('====================================================\n');

%% ===== LOCAL FUNCTIONS =====
function X = read_square_local(filename, n)
    raw = readmatrix(filename);
    raw = raw(~all(isnan(raw),2), :);
    raw = raw(:, ~all(isnan(raw),1));
    if size(raw,1) >= n && size(raw,2) >= n
        X = raw(end-n+1:end, end-n+1:end);
    else
        error('%s에서 %dx%d 추출 불가 (크기 %dx%d).', filename, n, n, size(raw,1), size(raw,2));
    end
    X = double(X); X(~isfinite(X)) = 0; X = 0.5*(X+X.');
end

function T = build_center_torsion_transform(pairFE, nNode)
    % 무손상 코드와 동일
    nPair = size(pairFE,1);
    T = zeros(nNode,nNode);
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
    % 무손상 코드와 동일 (scale = [Kc_G1..4 Kt_G1..4 Mc Mt])
    n = size(M,1); nHalf = n/2; nGroup = numel(groupStation);
    if length(scale) ~= 2*nGroup + 2
        error('scale length must be %d.', 2*nGroup + 2);
    end
    Kq = Tinv' * K * Tinv;  Mq = Tinv' * M * Tinv;
    Dk = eye(n); Dm = eye(n);
    for g = 1:nGroup
        idx = groupStation{g};
        Dk(idx,idx) = sqrt(scale(g))*eye(length(idx));
    end
    for g = 1:nGroup
        idx = nHalf + groupStation{g};
        Dk(idx,idx) = sqrt(scale(nGroup+g))*eye(length(idx));
    end
    Dm(1:nHalf,1:nHalf)       = sqrt(scale(2*nGroup+1))*eye(nHalf);
    Dm(nHalf+1:end,nHalf+1:end) = sqrt(scale(2*nGroup+2))*eye(nHalf);
    KqNew = Dk * Kq * Dk;  MqNew = Dm * Mq * Dm;
    Knew = T' * KqNew * T;  Mnew = T' * MqNew * T;
    Knew = 0.5*(Knew + Knew');  Mnew = 0.5*(Mnew + Mnew');
end
