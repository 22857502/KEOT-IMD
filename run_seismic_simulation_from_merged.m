%% run_seismic_simulation_from_merged.m
% ------------------------------------------------------------------
% 목적:
%   hangduri_24node_update_and_state_space_merged_final.m 실행 결과
%   (hangduri_24node_merged_result.mat)에 저장된 M, C, K를 불러와서
%   El-Centro 지진파를 지반가속도 입력으로 적용하고,
%   24개 노드의 절대가속도 응답을 시뮬레이션/플롯한다.
%
%   기존 merged 코드는 전혀 수정하지 않으며, 이 스크립트는 별도로 실행한다.
%
%   전제조건:
%     1) hangduri_24node_update_and_state_space_merged_final.m 을 먼저 실행하여
%        hangduri_24node_merged_result.mat 파일이 생성되어 있어야 함
%        (M0,K0,C0,Mup,Kup,Cup이 저장되어 있어야 함)
%     2) El-centro.xlsx 파일이 현재 폴더에 있어야 함 (1열=time[s], 2열=accel)
%     3) 아래 함수 파일들이 모두 MATLAB 경로에 있어야 함:
%          build_seismic_state_space.m
%          load_ground_motion_elcentro.m
%          simulate_seismic_response_24node.m
%          plot_seismic_acceleration_24node.m
%          (선택) build_caughey_damping_3term.m
% ------------------------------------------------------------------

% clear; clc; close all;

%% 1. 설정
mergedResultFile = 'hangduri_24node_merged_result.mat';
elcentroFile      = 'El-centro.xlsx';
elcentroUnit      = 'g';            % El-Centro 원본 단위: 'g' 또는 'm/s2' (파일 확인 후 설정)
dtTarget          = 0.01;           % 시뮬레이션에 사용할 시간간격 [s]
tEndSeismic       = [];             % [] 이면 El-Centro 전체 길이 사용
outputType        = 'absolute';     % 'absolute' 권장 (가속도계 실측과 직접 비교 가능)
outPrefix         = 'hangduri_24node_seismic';

% 감쇠행렬 소스 선택
%   'rayleigh_from_merged' : merged 파이프라인이 저장한 C0/Cup 재사용 (기본, 권장)
%   'caughey_3term'        : Damping.xlsx의 실측 모드별 감쇠비로 재계산
dampingSource = 'rayleigh_from_merged';

%% 2. FE Updating 결과(M, C, K) 로드
if exist(mergedResultFile, 'file') ~= 2
    error(['%s 파일을 찾을 수 없습니다. ', ...
           'hangduri_24node_update_and_state_space_merged_final.m 을 먼저 실행하세요.'], ...
           mergedResultFile);
end

S = load(mergedResultFile, 'M0','K0','C0','Mup','Kup','Cup');

fprintf('불러온 매트릭스 크기 확인: M0 = %dx%d, Mup = %dx%d\n', ...
    size(S.M0,1), size(S.M0,2), size(S.Mup,1), size(S.Mup,2));

C0  = S.C0;
Cup = S.Cup;

if strcmpi(dampingSource, 'caughey_3term')
    if exist('Damping.xlsx','file') ~= 2
        error('dampingSource = ''caughey_3term''이지만 Damping.xlsx를 찾을 수 없습니다.');
    end
    ep = readmatrix('Damping.xlsx');

    % 초기/업데이트 모델 각각의 모달 주파수로 재계산 (merged 결과에 저장된 값 사용)
    S2 = load(mergedResultFile, 'freq0Match', 'freqUpMatch');
    nModeDamp = min(length(ep), length(S2.freq0Match));

    C0  = build_caughey_damping_3term(S.M0,  S.K0,  S2.freq0Match(1:nModeDamp),  ep(1:nModeDamp));
    Cup = build_caughey_damping_3term(S.Mup, S.Kup, S2.freqUpMatch(1:nModeDamp), ep(1:nModeDamp));

    fprintf('감쇠행렬을 Damping.xlsx 기반 3-term Caughey 방식으로 재계산했습니다 (%d개 모드 사용).\n', nModeDamp);
else
    fprintf('감쇠행렬은 merged 파이프라인의 Rayleigh damping(C0, Cup)을 그대로 사용합니다.\n');
end

%% 3. El-Centro 지진파 로드
[t_eq, ag_raw, dt_orig] = load_ground_motion_elcentro(elcentroFile, elcentroUnit);
fprintf('El-Centro 원본 dt = %.6f s (%.1f Hz), 총 길이 = %.2f s\n', ...
    dt_orig, 1/dt_orig, t_eq(end)-t_eq(1));

% 시뮬레이션용 균일 시간축으로 재보간
if isempty(tEndSeismic)
    tEndSeismic = t_eq(end);
end
t  = (0:dtTarget:tEndSeismic).';
ag = interp1(t_eq, ag_raw, t, 'linear', 'extrap');

figure('Name','El-Centro ground motion');
plot(t, ag/9.80665, 'k-');
grid on;
xlabel('Time [s]');
ylabel('Ground accel [g]');
title('El-Centro input ground motion');
saveas(gcf, [outPrefix '_input_motion.png']);

%% 4. 초기/업데이트 모델 각각 지진응답 시뮬레이션
fprintf('\n초기 FE 모델(M0,K0,C0) 지진응답 시뮬레이션 중...\n');
result0 = simulate_seismic_response_24node(S.M0, C0, S.K0, t, ag, ...
    'OutputType', outputType, 'Label', 'Initial FE');

fprintf('업데이트 FE 모델(Mup,Kup,Cup) 지진응답 시뮬레이션 중...\n');
resultUp = simulate_seismic_response_24node(S.Mup, Cup, S.Kup, t, ag, ...
    'OutputType', outputType, 'Label', 'Updated FE');

%% 5. 결과 플롯
%    (a) N-line(1~12) / S-line(13~24)을 각각 별도 figure로 분리해서 표시
%        + 24노드 전체 최대응답 프로파일도 이 호출에서 함께 표시
%    (b) 24개 노드를 각각 별도 figure로 개별 plot
plot_seismic_acceleration_24node({result0, resultUp}, ...
    'PlotStyle', 'split_ns', ...
    'Unit', 'g', ...
    'OutPrefix', outPrefix, ...
    'ShowPeakProfile', true, ...
    'CommonYLim', true);      % 겹침 그림도 24절점 y축 동일 대칭범위(두 result 최대값 기준)

plot_seismic_acceleration_24node({result0, resultUp}, ...
    'PlotStyle', 'individual', ...
    'Unit', 'g', ...
    'OutPrefix', outPrefix, ...
    'ShowPeakProfile', false, ...
    'CommonYLim', true);

%% 6. 결과 저장 (.mat)
save([outPrefix '_result.mat'], 't', 'ag', 'result0', 'resultUp', ...
    'outputType', 'dtTarget', 'dampingSource');

%% 7. 추출된 가속도를 엑셀 파일로 저장
%    시트: Initial_FE, Updated_FE (각 시트: Time_s + Node_1 ~ Node_24, 단위 g)
export_accel_to_excel({result0, resultUp}, [outPrefix '_accel.xlsx'], ...
    'Unit', 'g', ...
    'SheetNames', {'Initial_FE','Updated_FE'});

fprintf('\n저장 완료:\n');
fprintf('  %s_result.mat\n', outPrefix);
fprintf('  %s_accel.xlsx  (시트: Initial_FE, Updated_FE)\n', outPrefix);
fprintf('  %s_input_motion.png\n', outPrefix);
fprintf('  %s_seismic_Nline.png\n', outPrefix);
fprintf('  %s_seismic_Sline.png\n', outPrefix);
fprintf('  %s_seismic_peak_profile.png\n', outPrefix);
fprintf('  %s_seismic_node01.png ~ %s_seismic_node24.png (24개)\n', outPrefix, outPrefix);
fprintf('\nDone.\n');

%% 5-2. [추가] 무손상(Updated FE) '단독' 24절점 그림 (겹침 그림은 그대로 둠)
%    별도 함수 없이, plot_seismic_acceleration_24node 를 {resultUp} 하나만 넘겨 재사용.
%    구성: 24-in-one 격자(1) + N선(1) + S선(1) + 개별(24) = 27장. 위 겹침 27장과 합쳐 무손상 54장.
%    'ShowLegend',false : 단독이라 선이 하나뿐 -> 범례 생략.
%    'CommonYLim',true  : 24개 노드 y축을 동일 대칭범위로 고정(절점 간 진폭 비교용).
%    peak 프로파일은 겹침 그림에만 두어 단독에서는 중복 생성하지 않음(ShowPeakProfile,false).
plot_seismic_acceleration_24node({resultUp}, ...
    'PlotStyle', 'grid', 'Unit', 'g', 'OutPrefix', '', 'CommonYLim', true, 'ShowLegend', false);
plot_seismic_acceleration_24node({resultUp}, ...
    'PlotStyle', 'split_ns', 'Unit', 'g', 'OutPrefix', '', 'ShowPeakProfile', false, 'CommonYLim', true, 'ShowLegend', false);
plot_seismic_acceleration_24node({resultUp}, ...
    'PlotStyle', 'individual', 'Unit', 'g', 'OutPrefix', '', 'ShowPeakProfile', false, 'CommonYLim', true, 'ShowLegend', false);

%% 모든 열린 figure를 .fig로 자동 저장 (PNG는 저장하지 않음)
save_all_figs_as_fig();

%% ---- 다음 실행 안내 (파이프라인 3/9 완료) ----
fprintf('\n================ 다음 실행 스크립트 ================\n');
fprintf('  [3/9] 무손상 지진응답 생성 완료  ->  hangduri_24node_seismic_accel.xlsx\n');
fprintf('  >> 다음 실행: run_seismic_simulation_damage_fixed.m\n');
fprintf('     (손상 4케이블 파단 지진응답 — 그림 7, hangduri_24node_cable4break_accel.xlsx)\n');
fprintf('====================================================\n');
