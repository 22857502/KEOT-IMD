%% hangduri_24node_update_and_state_space_merged_final.m
% -------------------------------------------------------------------------
% 한두리교 24-node FE 모델 기반
% 주파수 중심 FE Updating + 업데이트 M,K 기반 상태공간방정식 생성/응답 시뮬레이션 통합 코드
%
% 병합 대상:
%   1) haduri_24node_state_space_frequency_updating_v7.m
%      - 주파수 중심 FE Updating
%      - ordered mode matching
%      - center/torsion 4구간 stiffness scaling
%      - M_center, M_torsion 제한
%
%   2) hangduri_24node_updated_state_space_final.m
%      - 기존 업데이트 결과 Mup,Kup 또는 scaleOpt 자동 반영
%      - 업데이트 상태공간 A,B,C,D 생성
%      - 초기/업데이트 FE 모델 고유진동수 비교
%      - 상태공간 응답 시뮬레이션
%
% 본 통합 코드의 핵심 원칙:
%   - 최우선 목표는 고유진동수 일치
%   - Shape Vector / MAC는 FE eigenvector와 동일시하지 않음
%   - MAC는 optional 보조 검증이며 objective 기본 가중치 w_mac = 0
%   - runUpdating = true  : v7 방식으로 새 업데이트 수행 후 상태공간 생성
%   - runUpdating = false : 기존 결과 파일에서 Mup,Kup 또는 scaleOpt를 읽어 상태공간 생성
%
% 기본 운동방정식:
%   M*xddot + C*xdot + K*x = f
%
% 상태공간:
%   z = [x; xdot]
%   A = [0 I; -M\K -M\C]
%   B = [0; M\I]
%   Cout = [I 0]
%   D = 0
%
% 작성 주의:
%   - 파일 구조를 먼저 확인하고 24x24 숫자 행렬을 추출함
%   - 물리적으로 이상한 결과가 나오면 M,K, mapping, 단위, scale 적용 방식을 먼저 점검할 것
% -------------------------------------------------------------------------

clear; clc; close all;

%% ========================================================================
%  1. USER SETTINGS
% ========================================================================

% 실행 모드
runUpdating = true;     % true: 새 FE update 수행 / false: 기존 Mup,Kup 또는 scaleOpt 사용
doSimulation = true;    % 상태공간 응답 시뮬레이션 수행 여부

% 기본 모델 정보
nNode = 24;
nStation = 12;
nTargetMode = 9;
nModeCompare = 9;

% ===== 논문 보고용(Table 5 기준) 10개 목표 모드 — 그림/표 표시 전용 =====
% FE 보정 최적화에는 사용하지 않음(freqMeasured_default·nTargetMode 불변).
% 보정된 FE 모델의 가장 가까운 고유진동수에 대응시켜 Fig 2·3, Table 4를 생성한다(1.008Hz FE 모드는 자동 제외).
freqReport = [0.44970703125; 0.6435546875; 0.7294921875; 0.91064453125; 1.12158203125; ...
              1.38232421875; 1.54345703125; 1.67333984375; 1.9931640625; 2.1591796875]; % [Hz] Table 5 PSD 첨두(전정밀도, 기준)
dampReport = [1.92; 1.61; 1.23; 1.27; 0.93; ...
              0.99; 1.01; 0.98; 0.66; 0.80];             % [%] 계측 감쇠비(Table 4)

% FE 24-node pair: (1,13), (2,14), ..., (12,24)
pairFE = [(1:12)', (13:24)'];

% center/torsion 4개 station group
groupStation = cell(4,1);
groupStation{1} = 1:3;
groupStation{2} = 4:6;
groupStation{3} = 7:9;
groupStation{4} = 10:12;

% 좌우 계측선 거리 [m]
deck_width = 20.0;

% 입력 파일 후보
M_candidates = { ...
    'haduri_node24_M matrix(unit kg).xlsx', ...
    'haduri_node24_M matrix(unit kg)(1).xlsx', ...
    'hangduri_node24_M matrix(unit kg).xlsx', ...
    'hangduri_node24_M matrix(unit kg)(1).xlsx'};

K_candidates = { ...
    'haduri_node24_K matrix(unit N per m).xlsx', ...
    'haduri_node24_K matrix(unit N per m)(1).xlsx', ...
    'hangduri_node24_K matrix(unit N per m).xlsx', ...
    'hangduri_node24_K matrix(unit N per m)(1).xlsx'};

modal_candidates = { ...
    'Modal Data.xlsx', ...
    'Modal Data(1).xlsx', ...
    'modal data.xlsx', ...
    'modal_data.xlsx'};

shape_sheet = 'Shape Vector';

% 보고서 기준 3 Hz 이하 유효모드
% Code Mode 1 = Report Mode 1
% Code Mode 2 = Report Mode 2
% ...
% Code Mode 6 = Report Mode 6/7
% Code Mode 7 = Report Mode 8
% Code Mode 8 = Report Mode 9
% Code Mode 9 = Report Mode 10
freqMeasured_default = [
    0.449642
    0.646423
    0.728461
    0.912378
    1.008340
    1.122340
    1.379730
    1.539390
    1.681360
];

% 계측-해석 mapping
% 'drawing'    : 도면 기반 mapping
% 'sequential' : DOF 4~27 -> FE node 1~24
% 'swap_ns'    : drawing mapping의 N/S swap
mappingMode = 'drawing';

% Shape Vector 사용 방식
% 현재 기본값 false:
%   FE eigenvector를 reference ratio로 변환하지 않고 관측 FE node 값만 사용
%   단, MAC는 보조 검증일 뿐 objective에는 기본적으로 사용하지 않음
useReferenceRatio = false;

% Mode matching
modeMatchMethod = 'ordered';   % 고유진동수 중심, mode swapping 방지

% 보고서 기준 비틀림 관련 모드
torsion_mode_idx = [2 5 6 9];

% Frequency-only objective weights
w_freq = 1.00;
w_mac  = 0.00;  % Shape Vector/MAC는 기본적으로 objective에서 제외
w_reg  = 0.08;
w_maxerr = 0.15;  % 최대 주파수 오차 penalty

% 비틀림 모드 가중치
torsionModeWeight = 1.10;

% Updating scale bounds
% p = [
%      Kc_G1 Kc_G2 Kc_G3 Kc_G4 Kt_G1 Kt_G2 Kt_G3 Kt_G4 Mc Mt
%     ]
lb_scale = [0.55 0.55 0.55 0.55  0.55 0.55 0.55 0.55  0.98 0.98];
ub_scale = [2.20 2.20 2.20 2.20  2.60 2.60 2.60 2.60  1.02 1.02];
x0_scale = [1.00 1.00 1.00 1.00  1.00 1.00 1.00 1.00  1.00 1.00];

% Multi-start 설정
useMultiStart = true;
nRandomStart = 30;
rng(7);

% Rayleigh damping
zeta_target = 0.015;
rayleighMode1 = 1;
rayleighMode2 = 3;

% Example state-space response
force_node_example = 10;
force_N_example = -1000.0;
dt = 0.01;
tEnd = 20.0;
inputType = 'step';        % 'step', 'impulse_approx', 'sine'
sineFreqHz = 0.45;

% 출력 prefix
outPrefix = 'hangduri_24node_merged';

%% ========================================================================
%  2. FIND AND READ FE M,K MATRICES
% ========================================================================

fprintf('\n============================================================\n');
fprintf('1) Find and read FE M,K matrices\n');
fprintf('============================================================\n');

file_M24 = find_existing_file(M_candidates, true);
file_K24 = find_existing_file(K_candidates, true);

fprintf('M file = %s\n', file_M24);
fprintf('K file = %s\n', file_K24);

M0 = read_numeric_square_from_excel(file_M24, nNode);
K0 = read_numeric_square_from_excel(file_K24, nNode);
[M0, K0] = clean_and_check_MK(M0, K0);

matrixCheck0 = verify_matrix_pair(M0, K0, 'Initial');
disp(matrixCheck0);

if matrixCheck0.M_min_eig <= 0 || matrixCheck0.K_min_eig <= 0
    error('Initial M or K has non-positive eigenvalue. Check matrix files.');
end

%% ========================================================================
%  3. READ MODAL DATA OR USE DEFAULT FREQUENCY ONLY
% ========================================================================

fprintf('\n============================================================\n');
fprintf('2) Read modal data\n');
fprintf('============================================================\n');

file_modal = find_existing_file(modal_candidates, false);

if runUpdating
    if isempty(file_modal)
        warning('Modal Data.xlsx was not found. Updating will use default measured frequencies only. MAC/Shape Vector check is disabled.');
        expFreqHz = freqMeasured_default(1:nTargetMode);
        expPhiRaw = [];
        expPhi = [];
        respDof = [];
        refDof = [];
        dofLabel = {};
        useShapeData = false;
    else
        fprintf('Modal file = %s\n', file_modal);
        [expFreqHz, expPhiRaw, respDof, refDof, dofLabel] = read_shape_vector_modal_data(file_modal, shape_sheet);

        nUseMode = min([nTargetMode, length(expFreqHz), size(expPhiRaw,2)]);
        expFreqHz = expFreqHz(1:nUseMode);
        expPhiRaw = expPhiRaw(:,1:nUseMode);
        expPhi = normalize_columns(expPhiRaw);
        useShapeData = true;
    end
else
    if isempty(file_modal)
        expFreqHz = freqMeasured_default(1:nTargetMode);
        expPhiRaw = [];
        expPhi = [];
        respDof = [];
        refDof = [];
        dofLabel = {};
        useShapeData = false;
    else
        fprintf('Modal file = %s\n', file_modal);
        [expFreqHz, expPhiRaw, respDof, refDof, dofLabel] = read_shape_vector_modal_data(file_modal, shape_sheet);

        nUseMode = min([nTargetMode, length(expFreqHz), size(expPhiRaw,2)]);
        expFreqHz = expFreqHz(1:nUseMode);
        expPhiRaw = expPhiRaw(:,1:nUseMode);
        expPhi = normalize_columns(expPhiRaw);
        useShapeData = true;
    end
end

nUseMode = min(nTargetMode, length(expFreqHz));
expFreqHz = expFreqHz(1:nUseMode);

fprintf('Measured frequency count used = %d\n', nUseMode);
disp(table((1:nUseMode)', expFreqHz(:), 'VariableNames', {'Mode','Measured_Frequency_Hz'}));

%% ========================================================================
%  4. BUILD MEASUREMENT-TO-FE MAPPING
% ========================================================================

fprintf('\n============================================================\n');
fprintf('3) Build measurement DOF to FE node mapping\n');
fprintf('============================================================\n');

mapDrawing = build_drawing_mapping_table();

switch lower(mappingMode)
    case 'drawing'
        mapTable = mapDrawing;
    case 'sequential'
        mapTable = table((4:27)', (1:24)', repmat("sequential",24,1), ...
            'VariableNames', {'Meas_DOF','FE_Node','Location'});
    case 'swap_ns'
        mapTable = build_swap_ns_mapping_table(mapDrawing);
    otherwise
        error('Unknown mappingMode: %s', mappingMode);
end

disp(mapTable);
writetable(mapTable, [outPrefix '_mapping_table.xlsx']);

if useShapeData
    respFE = map_dof_to_fe(respDof, mapTable);
    refFE  = map_dof_to_fe(refDof,  mapTable);

    if any(isnan(respFE))
        error('Some response DOFs were not mapped to FE nodes.');
    end
else
    respFE = [];
    refFE = [];
end

%% ========================================================================
%  5. INITIAL FE MODAL ANALYSIS
% ========================================================================

fprintf('\n============================================================\n');
fprintf('4) Initial FE modal analysis\n');
fprintf('============================================================\n');

nCalcMode = max(16, nUseMode + 6);
[freq0Hz_all, Phi0_all] = modal_analysis_MK(M0, K0, nCalcMode);
Phi0_all = normalize_columns(Phi0_all);

if useShapeData
    Phi0Obs_all = fe_modes_to_observation_modes(Phi0_all, respFE, refFE, useReferenceRatio);
    Phi0Obs_all = normalize_columns(Phi0Obs_all);

    [modeMap0, freq0Match, Phi0ObsMatch, mac0, MAC0] = match_modes( ...
        expFreqHz, expPhi, freq0Hz_all, Phi0Obs_all, modeMatchMethod);
else
    Phi0Obs_all = [];
    Phi0ObsMatch = [];
    MAC0 = [];
    modeMap0 = (1:nUseMode).';
    freq0Match = freq0Hz_all(1:nUseMode);
    mac0 = nan(nUseMode,1);
end

freqErrBefore = 100*(freq0Match(:)-expFreqHz(:))./expFreqHz(:);

initialTable = table((1:nUseMode)', expFreqHz(:), freq0Match(:), freqErrBefore(:), mac0(:), modeMap0(:), ...
    'VariableNames', {'Mode','Measured_Hz','Initial_FE_Hz','Initial_Error_percent','MAC_Before','Matched_FE_Mode'});

disp(initialTable);

%% ========================================================================
%  6. UPDATE OR LOAD UPDATED M,K
% ========================================================================

fprintf('\n============================================================\n');
fprintf('5) FE updating or loading updated M,K\n');
fprintf('============================================================\n');

T = build_center_torsion_transform(pairFE, nNode);
Tinv = inv(T);

if runUpdating
    fprintf('runUpdating = true: v7 frequency-based updating will be performed.\n');

    if ~useShapeData
        % Shape Vector가 없을 경우에도 frequency-only 업데이트 가능하도록 dummy observation 사용
        expPhi_dummy = eye(nUseMode);
        expPhi_for_obj = expPhi_dummy;
        respFE_for_obj = (1:nUseMode).';
        refFE_for_obj = respFE_for_obj;
        useReferenceRatio_for_obj = false;
        modeMatch_for_obj = 'ordered_frequency_only';
    else
        expPhi_for_obj = expPhi;
        respFE_for_obj = respFE;
        refFE_for_obj = refFE;
        useReferenceRatio_for_obj = useReferenceRatio;
        modeMatch_for_obj = modeMatchMethod;
    end

    x0 = log(x0_scale(:));
    lb = log(lb_scale(:));
    ub = log(ub_scale(:));

    objfun = @(x) objective_frequency_update_v7_merged( ...
        x, M0, K0, T, Tinv, groupStation, expFreqHz, expPhi_for_obj, respFE_for_obj, refFE_for_obj, ...
        useReferenceRatio_for_obj, nCalcMode, nUseMode, modeMatch_for_obj, ...
        torsion_mode_idx, torsionModeWeight, w_freq, w_mac, w_reg, w_maxerr);

    bestX = x0;
    bestF = objfun(x0);

    if exist('fmincon','file') == 2
        opts = optimoptions('fmincon', ...
            'Display','iter', ...
            'Algorithm','sqp', ...
            'MaxFunctionEvaluations', 5000, ...
            'MaxIterations', 500, ...
            'StepTolerance', 1e-11, ...
            'OptimalityTolerance', 1e-10);

        startList = x0(:)';

        if useMultiStart
            for r = 1:nRandomStart
                randScale = lb_scale(:)' + rand(1,length(lb_scale)).*(ub_scale(:)'-lb_scale(:)');
                randScale = 0.50*randScale + 0.50*ones(size(randScale));
                startList = [startList; log(randScale)]; %#ok<AGROW>
            end
        end

        for s = 1:size(startList,1)
            fprintf('\n--- Optimization start %d / %d ---\n', s, size(startList,1));
            xStart = startList(s,:)';
            try
                [xTry, fTry] = fmincon(objfun, xStart, [], [], [], [], lb, ub, [], opts);
            catch ME
                warning('fmincon failed at start %d: %s', s, ME.message);
                continue;
            end

            fprintf('Start %d objective = %.6e\n', s, fTry);

            if fTry < bestF
                bestF = fTry;
                bestX = xTry;
            end
        end

        xOpt = bestX;
        fval = bestF;
    else
        warning('fmincon is not available. Using fminsearch with bounded transform.');
        opts = optimset('Display','iter', 'MaxFunEvals', 5000, 'MaxIter', 700);
        y0 = zeros(size(x0));
        yOpt = fminsearch(@(y) objfun(bound_transform(y, lb, ub)), y0, opts);
        xOpt = bound_transform(yOpt, lb, ub);
        fval = objfun(xOpt);
    end

    scaleOpt = exp(xOpt(:));
    [Mup, Kup] = apply_group_center_torsion_scaling(M0, K0, T, Tinv, groupStation, scaleOpt);
    [Mup, Kup] = clean_and_check_MK(Mup, Kup);

    updateSource = 'New v7 frequency-based updating performed in merged code';

else
    fprintf('runUpdating = false: existing Mup,Kup or scaleOpt will be loaded.\n');
    [Mup, Kup, scaleOpt, updateSource] = load_updated_MK_or_scale_merged(M0, K0, pairFE, groupStation);
    [Mup, Kup] = clean_and_check_MK(Mup, Kup);
    fval = nan;
end

fprintf('Update source = %s\n', updateSource);

if ~isempty(scaleOpt)
    paramNames = {'Kc_G1','Kc_G2','Kc_G3','Kc_G4', ...
                  'Kt_G1','Kt_G2','Kt_G3','Kt_G4', ...
                  'M_center','M_torsion'}';

    if length(scaleOpt) == 10
        paramTable = table(paramNames, scaleOpt(:), ...
            'VariableNames', {'Parameter','Scale'});
    elseif length(scaleOpt) == 4
        paramTable = table({'K_center';'K_torsion';'M_center';'M_torsion'}, scaleOpt(:), ...
            'VariableNames', {'Parameter','Scale'});
    else
        paramTable = table((1:length(scaleOpt))', scaleOpt(:), ...
            'VariableNames', {'Parameter_Index','Scale'});
    end
else
    paramTable = table();
end

paramSummary = table(fval, w_freq, w_mac, w_reg, w_maxerr, torsionModeWeight, ...
    'VariableNames', {'Objective','W_freq','W_MAC','W_reg','W_maxerr','TorsionModeWeight'});

disp(paramTable);
disp(paramSummary);

if ~isempty(paramTable)
    writetable(paramTable, [outPrefix '_parameter_table.xlsx'], 'Sheet', 'Scale');
end
writetable(paramSummary, [outPrefix '_parameter_table.xlsx'], 'Sheet', 'Summary');

matrixCheckUp = verify_matrix_pair(Mup, Kup, 'Updated');
disp(matrixCheckUp);

if matrixCheckUp.M_min_eig <= 0 || matrixCheckUp.K_min_eig <= 0
    error('Updated Mup or Kup has non-positive eigenvalue.');
end

matrixInfo = [matrixCheck0; matrixCheckUp];
writetable(matrixInfo, [outPrefix '_matrix_info.xlsx']);

%% ========================================================================
%  7. UPDATED MODAL ANALYSIS AND COMPARISON
% ========================================================================

fprintf('\n============================================================\n');
fprintf('6) Updated FE modal analysis and comparison\n');
fprintf('============================================================\n');

[freqUpHz_all, PhiUp_all] = modal_analysis_MK(Mup, Kup, nCalcMode);
PhiUp_all = normalize_columns(PhiUp_all);

if useShapeData
    PhiUpObs_all = fe_modes_to_observation_modes(PhiUp_all, respFE, refFE, useReferenceRatio);
    PhiUpObs_all = normalize_columns(PhiUpObs_all);

    [modeMapUp, freqUpMatch, PhiUpObsMatch, macUp, MACup] = match_modes( ...
        expFreqHz, expPhi, freqUpHz_all, PhiUpObs_all, modeMatchMethod);
else
    PhiUpObs_all = [];
    PhiUpObsMatch = [];
    MACup = [];
    modeMapUp = (1:nUseMode).';
    freqUpMatch = freqUpHz_all(1:nUseMode);
    macUp = nan(nUseMode,1);
end

freqErrAfter  = 100*(freqUpMatch(:)-expFreqHz(:))./expFreqHz(:);
absErrBefore = abs(freqErrBefore);
absErrAfter  = abs(freqErrAfter);

modeType0 = classify_modes_center_torsion(Phi0_all(:,1:nUseMode), pairFE);
modeTypeUp = classify_modes_center_torsion(PhiUp_all(:,1:nUseMode), pairFE);

resultTable = table((1:nUseMode)', expFreqHz(:), freq0Match(:), freqUpMatch(:), ...
    freqErrBefore(:), freqErrAfter(:), absErrBefore(:), absErrAfter(:), ...
    mac0(:), macUp(:), modeMap0(:), modeMapUp(:), ...
    modeType0.Type(:), modeTypeUp.Type(:), ...
    modeType0.BendingIndex(:), modeType0.TorsionIndex(:), ...
    modeTypeUp.BendingIndex(:), modeTypeUp.TorsionIndex(:), ...
    'VariableNames', {'Mode','Measured_Hz','Before_Hz','After_Hz', ...
    'Before_Error_percent','After_Error_percent', ...
    'Before_AbsError_percent','After_AbsError_percent', ...
    'MAC_Before','MAC_After', ...
    'Matched_FE_Mode_Before','Matched_FE_Mode_After', ...
    'Initial_Mode_Type','Updated_Mode_Type', ...
    'Initial_Bending_Index','Initial_Torsion_Index', ...
    'Updated_Bending_Index','Updated_Torsion_Index'});

disp(resultTable);

fprintf('\nMean abs frequency error before = %.4f %%\n', mean(absErrBefore));
fprintf('Mean abs frequency error after  = %.4f %%\n', mean(absErrAfter));
fprintf('Max abs frequency error before  = %.4f %%\n', max(absErrBefore));
fprintf('Max abs frequency error after   = %.4f %%\n', max(absErrAfter));

writetable(resultTable, [outPrefix '_frequency_table.xlsx']);

if useShapeData
    writematrix(MAC0,  [outPrefix '_MAC_before.xlsx']);
    writematrix(MACup, [outPrefix '_MAC_after.xlsx']);
end

%% ========================================================================
%  8. BUILD RAYLEIGH DAMPING AND STATE-SPACE MODELS
% ========================================================================

fprintf('\n============================================================\n');
fprintf('7) Build Rayleigh damping and state-space models\n');
fprintf('============================================================\n');

rMode1 = min(rayleighMode1, nUseMode);
rMode2 = min(rayleighMode2, nUseMode);

[C0, alpha0, beta0] = build_rayleigh_damping(M0, K0, freq0Match(rMode1), freq0Match(rMode2), zeta_target);
[Cup, alphaUp, betaUp] = build_rayleigh_damping(Mup, Kup, freqUpMatch(rMode1), freqUpMatch(rMode2), zeta_target);

fprintf('Initial Rayleigh alpha = %.6e, beta = %.6e\n', alpha0, beta0);
fprintf('Updated Rayleigh alpha = %.6e, beta = %.6e\n', alphaUp, betaUp);

%% ========================================================================
%  7-R. REPORTING TABLES/FIGURES (Table 5 기준 10모드; 보정 결과 재사용)
% ========================================================================
% 보정 최적화 결과(freq0Hz_all, freqUpHz_all, alphaUp, betaUp)를 그대로 사용한다.
% 각 보고 모드를 보정된 FE 모델의 가장 가까운 고유진동수에 대응(1.008Hz FE 모드는 자동 제외).
nR = numel(freqReport);
feIdxR = zeros(nR,1); initReport = zeros(nR,1); updReport = zeros(nR,1);
for k = 1:nR
    [~, iu] = min(abs(freqUpHz_all - freqReport(k)));
    feIdxR(k)     = iu;
    initReport(k) = freq0Hz_all(iu);
    updReport(k)  = freqUpHz_all(iu);
end
if numel(unique(feIdxR)) < nR
    warning('reporting:dupFE', '보고 모드가 동일 FE 모드에 중복 대응되었습니다. freqReport를 확인하세요.');
end
errInitR = 100*(initReport - freqReport)./freqReport;
errUpR   = 100*(updReport   - freqReport)./freqReport;
absInitR = abs(errInitR); absUpR = abs(errUpR);
meanInitR = mean(absInitR); meanUpR = mean(absUpR);
maxInitR  = max(absInitR);  maxUpR  = max(absUpR);
fprintf('\n[Reporting] %d개 모드 평균 절대오차: %.2f%% -> %.2f%%\n', nR, meanInitR, meanUpR);
fprintf('[Reporting] %d개 모드 최대 절대오차: %.2f%% -> %.2f%%\n', nR, maxInitR, maxUpR);

% Table 2(보고용): 계측 vs 초기/업데이트 FE 고유진동수
table2Report = table((1:nR)', freqReport, initReport, updReport, absInitR, absUpR, ...
    'VariableNames', {'Mode','Measured_Hz','Initial_FE_Hz','Updated_FE_Hz', ...
    'Before_AbsError_percent','After_AbsError_percent'});
writetable(table2Report, [outPrefix '_frequency_table_report.xlsx']);

% Table 4(보고용): 계측 감쇠비 vs Rayleigh 유효 감쇠비(업데이트 모델 alphaUp,betaUp 사용)
wR = 2*pi*freqReport;
zetaRayReport = (alphaUp ./ (2*wR) + betaUp*wR/2) * 100;   % [%]
diffReport = zetaRayReport - dampReport;                   % Rayleigh - 계측 [%p]
table4Report = table((1:nR)', freqReport, dampReport, zetaRayReport, diffReport, ...
    'VariableNames', {'Mode','Freq_Hz','Measured_damping_percent', ...
    'Rayleigh_damping_percent','Diff_percentpoint'});
disp('Table 4 (reporting) measured vs Rayleigh damping:'); disp(table4Report);
writetable(table4Report, [outPrefix '_table4_damping_report.xlsx']);

[A0, B0, Cdisp0, D0]     = build_state_space(M0,  C0,  K0);
[Aup, Bup, CdispUp, Dup] = build_state_space(Mup, Cup, Kup);

fprintf('Before updating: A = %d x %d, B = %d x %d, C = %d x %d, D = %d x %d\n', ...
    size(A0,1), size(A0,2), size(B0,1), size(B0,2), size(Cdisp0,1), size(Cdisp0,2), size(D0,1), size(D0,2));
fprintf('After  updating: A = %d x %d, B = %d x %d, C = %d x %d, D = %d x %d\n', ...
    size(Aup,1), size(Aup,2), size(Bup,1), size(Bup,2), size(CdispUp,1), size(CdispUp,2), size(Dup,1), size(Dup,2));

%% ========================================================================
%  9. STATE-SPACE RESPONSE SIMULATION
% ========================================================================

if doSimulation
    fprintf('\n============================================================\n');
    fprintf('8) State-space response simulation\n');
    fprintf('============================================================\n');

    t = (0:dt:tEnd).';
    u = zeros(length(t), nNode);

    switch lower(inputType)
        case 'step'
            u(:,force_node_example) = force_N_example;
        case 'impulse_approx'
            u(1,force_node_example) = force_N_example/dt;
        case 'sine'
            u(:,force_node_example) = force_N_example*sin(2*pi*sineFreqHz*t);
        otherwise
            error('Unknown inputType: %s', inputType);
    end

    sys0  = ss(A0,  B0,  Cdisp0,  D0);
    sysUp = ss(Aup, Bup, CdispUp, Dup);

    y0  = lsim(sys0,  u, t);
    yUp = lsim(sysUp, u, t);

    [center0, torsion0]   = compute_center_torsion_response(y0,  pairFE, deck_width);
    [centerUp, torsionUp] = compute_center_torsion_response(yUp, pairFE, deck_width);

    fprintf('Simulation completed. Output yUp size = %d x %d\n', size(yUp,1), size(yUp,2));
else
    t = [];
    u = [];
    y0 = [];
    yUp = [];
    center0 = [];
    torsion0 = [];
    centerUp = [];
    torsionUp = [];
end

%% ========================================================================
%  10. PLOTS
% ========================================================================

fprintf('\n============================================================\n');
fprintf('9) Plot and save figures\n');
fprintf('============================================================\n');

figure('Name','Frequency comparison (reporting)');
hold on;
h1 = plot(1:nR, freqReport, 'ko-', 'LineWidth', 1.8);
h2 = plot(1:nR, initReport, 'bs-', 'LineWidth', 1.8);
h3 = plot(1:nR, updReport,  'r^-', 'LineWidth', 1.8);
grid on; box on; xlim([0.5 nR+0.5]); set(gca,'XTick',1:nR);
xlabel('Mode number');
ylabel('Frequency [Hz]');
title('Measured vs Initial FE vs Updated FE frequency');
legend([h1 h2 h3],'Measured','Initial FE','Updated FE','Location','northwest');
saveas(gcf, [outPrefix '_frequency_comparison.png']);

figure('Name','Frequency error merged');
bar([errInitR(:), errUpR(:)]);
grid on; xlim([0.5 nR+0.5]); set(gca,'XTick',1:nR);
xlabel('Mode number');
ylabel('Frequency error [%]');
title('Frequency error before and after updating');
legend('Initial FE','Updated FE','Location','best');
saveas(gcf, [outPrefix '_frequency_error.png']);

figure('Name','Absolute frequency error (reporting)');
bar([absInitR(:), absUpR(:)]);
grid on; xlim([0.5 nR+0.5]); set(gca,'XTick',1:nR);
xlabel('Mode number');
ylabel('Absolute frequency error [%]');
title('Absolute frequency error before and after updating');
legend('Initial FE','Updated FE','Location','northeast');
saveas(gcf, [outPrefix '_abs_frequency_error.png']);

if useShapeData
    figure('Name','MAC comparison merged');
    bar([mac0(:), macUp(:)]);
    grid on;
    xlabel('Mode number');
    ylabel('MAC');
    ylim([0 1]);
    title('MAC comparison, optional validation only');
    legend('Before','After','Location','best');
    saveas(gcf, [outPrefix '_MAC_comparison.png']);

    figure('Name','MAC matrix before merged');
    imagesc(MAC0);
    axis equal tight;
    colorbar;
    xlabel('FE mode');
    ylabel('Experimental mode');
    title('MAC matrix before updating');
    saveas(gcf, [outPrefix '_MAC_matrix_before.png']);

    figure('Name','MAC matrix after merged');
    imagesc(MACup);
    axis equal tight;
    colorbar;
    xlabel('FE mode');
    ylabel('Experimental mode');
    title('MAC matrix after updating');
    saveas(gcf, [outPrefix '_MAC_matrix_after.png']);

    modePlotList = unique([1 2 5 6 9]);
    modePlotList = modePlotList(modePlotList <= nUseMode);

    for k = modePlotList
        figure('Name',sprintf('Mode shape comparison mode %d',k));
        plot(1:length(respDof), expPhi(:,k), 'ko-', 'LineWidth', 1.5); hold on;
        plot(1:length(respDof), Phi0ObsMatch(:,k), 'bs-', 'LineWidth', 1.5);
        plot(1:length(respDof), PhiUpObsMatch(:,k), 'r^-', 'LineWidth', 1.5);
        grid on;
        xlabel('Measurement row');
        ylabel('Normalized modal ordinate');
        title(sprintf('Mode %d shape comparison, MAC optional only', k));
        legend('Measured','FE before','FE after','Location','best');
        saveas(gcf, sprintf('%s_mode_shape_%02d.png', outPrefix, k));
    end
end

if doSimulation
    figure('Name','Example displacement response merged');
    plot(t, y0(:,force_node_example), 'b-', 'LineWidth', 1.2); hold on;
    plot(t, yUp(:,force_node_example), 'r--', 'LineWidth', 1.2);
    grid on;
    xlabel('Time [s]');
    ylabel('Displacement [m]');
    title(sprintf('State-space displacement response at FE node %d', force_node_example));
    legend('Initial FE','Updated FE','Location','best');
    saveas(gcf, sprintf('%s_state_response_node%02d.png', outPrefix, force_node_example));

    station_id = min(force_node_example, 12);

    figure('Name','Example center response merged');
    plot(t, center0(:,station_id), 'b-', 'LineWidth', 1.2); hold on;
    plot(t, centerUp(:,station_id), 'r--', 'LineWidth', 1.2);
    grid on;
    xlabel('Time [s]');
    ylabel('Center displacement [m]');
    title(sprintf('Center response at station %d', station_id));
    legend('Initial FE','Updated FE','Location','best');
    saveas(gcf, sprintf('%s_center_response_station%02d.png', outPrefix, station_id));

    figure('Name','Example torsion response merged');
    plot(t, torsion0(:,station_id), 'b-', 'LineWidth', 1.2); hold on;
    plot(t, torsionUp(:,station_id), 'r--', 'LineWidth', 1.2);
    grid on;
    xlabel('Time [s]');
    ylabel('Approx. torsion angle [rad]');
    title(sprintf('Torsion response at station %d', station_id));
    legend('Initial FE','Updated FE','Location','best');
    saveas(gcf, sprintf('%s_torsion_response_station%02d.png', outPrefix, station_id));
end

%% ========================================================================
%  11. SAVE FINAL MODEL
% ========================================================================

fprintf('\n============================================================\n');
fprintf('10) Save final merged model\n');
fprintf('============================================================\n');

save([outPrefix '_result.mat'], ...
    'runUpdating','doSimulation', ...
    'M0','K0','Mup','Kup','C0','Cup', ...
    'A0','B0','Cdisp0','D0','Aup','Bup','CdispUp','Dup', ...
    'alpha0','beta0','alphaUp','betaUp', ...
    'expFreqHz','freq0Hz_all','Phi0_all','freq0Match','modeMap0','mac0','MAC0', ...
    'freqUpHz_all','PhiUp_all','freqUpMatch','modeMapUp','macUp','MACup', ...
    'freqErrBefore','freqErrAfter','resultTable','initialTable', ...
    'expPhi','expPhiRaw','respDof','refDof','dofLabel','respFE','refFE','mapTable', ...
    'pairFE','deck_width','groupStation','scaleOpt','paramTable','paramSummary','updateSource', ...
    'zeta_target','alpha0','beta0','alphaUp','betaUp', ...
    'force_node_example','force_N_example','inputType','dt','tEnd','sineFreqHz', ...
    't','u','y0','yUp','center0','torsion0','centerUp','torsionUp', ...
    'w_freq','w_mac','w_reg','w_maxerr','torsionModeWeight');

fprintf('\nSaved files:\n');
fprintf('  %s_result.mat\n', outPrefix);
fprintf('  %s_frequency_table.xlsx\n', outPrefix);
fprintf('  %s_parameter_table.xlsx\n', outPrefix);
fprintf('  %s_mapping_table.xlsx\n', outPrefix);
fprintf('  %s_matrix_info.xlsx\n', outPrefix);
fprintf('  %s_*.png\n', outPrefix);
fprintf('\nDone.\n');

%% 모든 열린 figure를 .fig로 자동 저장 (PNG는 저장하지 않음)
save_all_figs_as_fig();

%% ---- 다음 실행 안내 (파이프라인 1/9 완료) ----
fprintf('\n================ 다음 실행 스크립트 ================\n');
fprintf('  [1/9] 모델 갱신 완료  ->  hangduri_24node_merged_result.mat 생성\n');
fprintf('  >> 다음 실행: hangduri_24node_damage_merged_fixed.m\n');
fprintf('     (상태공간 변위 응답 검증 — 그림 3·4, 절점10 계단하중)\n');
fprintf('====================================================\n');

%% ========================================================================
%  LOCAL FUNCTIONS
% ========================================================================

function filename = find_existing_file(candidates, required)
    filename = '';
    for i = 1:length(candidates)
        if exist(candidates{i}, 'file') == 2
            filename = candidates{i};
            return;
        end
    end

    if required
        error('Required file not found. Checked: %s', strjoin(candidates, ', '));
    end
end

function X = read_numeric_square_from_excel(filename, n)
    if exist(filename,'file') ~= 2
        error('File not found: %s', filename);
    end

    raw = readmatrix(filename);
    raw = raw(~all(isnan(raw),2), :);
    raw = raw(:, ~all(isnan(raw),1));

    if size(raw,1) == n && size(raw,2) == n
        X = raw;
    elseif size(raw,1) >= n && size(raw,2) >= n
        X = raw(end-n+1:end, end-n+1:end);
    else
        error('Cannot extract %d x %d matrix from %s.', n, n, filename);
    end

    X = double(X);
    X(~isfinite(X)) = 0;
end

function [M, K] = clean_and_check_MK(M, K)
    M = double(M);
    K = double(K);

    M(~isfinite(M)) = 0;
    K(~isfinite(K)) = 0;

    M = 0.5*(M + M');
    K = 0.5*(K + K');

    evM = eig(M);
    evK = eig(K);

    if min(evM) <= 0
        warning('M has non-positive eigenvalue. min eig(M) = %.4e', min(evM));
    end

    if min(evK) <= 0
        warning('K has non-positive eigenvalue. min eig(K) = %.4e', min(evK));
    end
end

function TBL = verify_matrix_pair(M, K, label)
    evM = eig(M);
    evK = eig(K);

    TBL = table( ...
        string(label), size(M,1), size(M,2), size(K,1), size(K,2), ...
        max(max(abs(M-M.'))), max(max(abs(K-K.'))), ...
        rank(M), rank(K), min(evM), min(evK), cond(M), cond(K), ...
        'VariableNames', { ...
        'Model','M_size_1','M_size_2','K_size_1','K_size_2', ...
        'M_sym_abs_max','K_sym_abs_max','M_rank','K_rank', ...
        'M_min_eig','K_min_eig','M_cond','K_cond'});
end

function [freqHz, Phi, respDof, refDof, labels] = read_shape_vector_modal_data(filename, sheetname)
    if exist(filename,'file') ~= 2
        error('File not found: %s', filename);
    end

    C = readcell(filename, 'Sheet', sheetname);

    freqRow = 3;
    firstModeCol = 3;

    freqHz = [];
    col = firstModeCol;

    while col <= size(C,2)
        v = C{freqRow,col};
        if isnumeric(v) && isscalar(v) && ~isnan(v)
            freqHz(end+1,1) = v; %#ok<AGROW>
            col = col + 1;
        else
            break;
        end
    end

    if isempty(freqHz)
        error('No modal frequencies found in row 3 of sheet "%s".', sheetname);
    end

    dataStartRow = 7;
    labels = {};
    respDof = [];
    refDof = [];
    Phi = [];

    r = dataStartRow;
    while r <= size(C,1)
        label = C{r,2};

        if ~(ischar(label) || isstring(label))
            break;
        end

        label = char(label);
        tok = regexp(label, '(\d+)\s*Z\s*:\s*(\d+)\s*Z', 'tokens', 'once');

        if isempty(tok)
            break;
        end

        labels{end+1,1} = label; %#ok<AGROW>
        respDof(end+1,1) = str2double(tok{1}); %#ok<AGROW>
        refDof(end+1,1)  = str2double(tok{2}); %#ok<AGROW>

        rowVals = nan(1,length(freqHz));
        for k = 1:length(freqHz)
            v = C{r,firstModeCol+k-1};
            if isnumeric(v)
                rowVals(k) = v;
            end
        end

        Phi(end+1,:) = rowVals; %#ok<AGROW>
        r = r + 1;
    end

    if isempty(Phi)
        error('No shape vector rows found. Expected labels like "4Z:19Z".');
    end

    Phi = double(Phi);
end

function mapTable = build_drawing_mapping_table()
    locN = strings(12,1);
    locS = strings(12,1);

    for i = 1:12
        locN(i) = "N" + string(i);
        locS(i) = "S" + string(i);
    end

    dofN = (15:-1:4)';
    dofS = (27:-1:16)';

    feN = (12:-1:1)';
    feS = (24:-1:13)';

    mapTable = table([dofN; dofS], [feN; feS], [locN; locS], ...
        'VariableNames', {'Meas_DOF','FE_Node','Location'});

    mapTable = sortrows(mapTable, 'Meas_DOF');
end

function mapTableSwap = build_swap_ns_mapping_table(mapTable)
    mapTableSwap = mapTable;

    for i = 1:height(mapTableSwap)
        fn = mapTableSwap.FE_Node(i);
        if fn <= 12
            mapTableSwap.FE_Node(i) = fn + 12;
        else
            mapTableSwap.FE_Node(i) = fn - 12;
        end
    end

    mapTableSwap.Location = mapTableSwap.Location + "_swapNS";
end

function feNode = map_dof_to_fe(dofList, mapTable)
    feNode = nan(size(dofList));

    for i = 1:length(dofList)
        idx = find(mapTable.Meas_DOF == dofList(i), 1);
        if ~isempty(idx)
            feNode(i) = mapTable.FE_Node(idx);
        end
    end
end

function [freqHz, Phi] = modal_analysis_MK(M, K, nMode)
    [V,D] = eig(K, M);

    lam = real(diag(D));
    valid = lam > 0 & isfinite(lam);

    lam = lam(valid);
    V = real(V(:,valid));

    freq = sqrt(lam)/(2*pi);
    [freqHz, idx] = sort(freq, 'ascend');
    Phi = V(:,idx);

    nMode = min(nMode, length(freqHz));
    freqHz = freqHz(1:nMode);
    Phi = Phi(:,1:nMode);
end

function PhiN = normalize_columns(Phi)
    PhiN = double(Phi);
    PhiN(~isfinite(PhiN)) = 0;

    for j = 1:size(PhiN,2)
        v = PhiN(:,j);
        mx = max(abs(v));

        if mx > 0
            v = v / mx;
        end

        [~,idx] = max(abs(v));
        if ~isempty(idx) && v(idx) < 0
            v = -v;
        end

        PhiN(:,j) = v;
    end
end

function PhiObs = fe_modes_to_observation_modes(PhiFE, respFE, refFE, useReferenceRatio)
    nObs = length(respFE);
    nMode = size(PhiFE,2);
    PhiObs = zeros(nObs,nMode);

    for k = 1:nMode
        for i = 1:nObs
            rNode = respFE(i);

            if useReferenceRatio
                refNode = refFE(i);
                den = PhiFE(refNode,k);

                if abs(den) < 1e-12
                    PhiObs(i,k) = 0;
                else
                    PhiObs(i,k) = PhiFE(rNode,k) / den;
                end
            else
                PhiObs(i,k) = PhiFE(rNode,k);
            end
        end
    end
end

function [modeMap, freqMatch, PhiMatch, macDiag, MACmat] = match_modes(expFreqHz, PhiExp, freqFE, PhiFEObs, method)
    nExp = length(expFreqHz);
    nFE = length(freqFE);

    if strcmpi(method, 'ordered_frequency_only')
        modeMap = (1:nExp).';
        freqMatch = freqFE(1:nExp);
        PhiMatch = [];
        macDiag = nan(nExp,1);
        MACmat = [];
        return;
    end

    MACmat = zeros(nExp,nFE);

    for i = 1:nExp
        for j = 1:nFE
            MACmat(i,j) = mac_value(PhiExp(:,i), PhiFEObs(:,j));
        end
    end

    modeMap = zeros(nExp,1);

    switch lower(method)
        case 'ordered'
            for i = 1:nExp
                modeMap(i) = i;
            end

        case 'combined'
            available = 1:nFE;

            for i = 1:nExp
                bestCost = inf;
                bestJ = available(1);

                for j = available
                    fcost = abs(log(freqFE(j)/expFreqHz(i)));
                    mcost = 1 - MACmat(i,j);
                    cost = 0.70*fcost + 0.30*mcost;

                    if cost < bestCost
                        bestCost = cost;
                        bestJ = j;
                    end
                end

                modeMap(i) = bestJ;
                available(available == bestJ) = [];

                if isempty(available)
                    available = 1:nFE;
                end
            end

        otherwise
            error('Unknown mode matching method: %s', method);
    end

    freqMatch = zeros(nExp,1);
    PhiMatch = zeros(size(PhiExp,1),nExp);
    macDiag = zeros(nExp,1);

    for i = 1:nExp
        j = modeMap(i);
        freqMatch(i) = freqFE(j);
        PhiMatch(:,i) = PhiFEObs(:,j);
        macDiag(i) = MACmat(i,j);

        if dot(PhiExp(:,i), PhiMatch(:,i)) < 0
            PhiMatch(:,i) = -PhiMatch(:,i);
        end
    end

    PhiMatch = normalize_columns(PhiMatch);
end

function m = mac_value(a,b)
    a = a(:);
    b = b(:);

    den = (a'*a)*(b'*b);

    if den <= eps
        m = 0;
    else
        m = abs(a'*b)^2 / den;
    end
end

function T = build_center_torsion_transform(pairFE, nNode)
    nPair = size(pairFE,1);
    T = zeros(nNode,nNode);

    for i = 1:nPair
        L = pairFE(i,1);
        R = pairFE(i,2);
        T(i,L) = 0.5;
        T(i,R) = 0.5;
    end

    for i = 1:nPair
        L = pairFE(i,1);
        R = pairFE(i,2);
        T(nPair+i,L) = 0.5;
        T(nPair+i,R) = -0.5;
    end
end

function [Mnew, Knew] = apply_group_center_torsion_scaling(M, K, T, Tinv, groupStation, scale)
    % scale = [Kc_G1...Kc_Gn Kt_G1...Kt_Gn Mc Mt]

    n = size(M,1);
    nHalf = n/2;
    nGroup = numel(groupStation);

    if length(scale) ~= 2*nGroup + 2
        error('For group scaling, scale length must be %d.', 2*nGroup + 2);
    end

    Kq = Tinv' * K * Tinv;
    Mq = Tinv' * M * Tinv;

    Dk = eye(n);
    Dm = eye(n);

    for g = 1:nGroup
        idx = groupStation{g};
        Dk(idx,idx) = sqrt(scale(g))*eye(length(idx));
    end

    for g = 1:nGroup
        idx = nHalf + groupStation{g};
        Dk(idx,idx) = sqrt(scale(nGroup+g))*eye(length(idx));
    end

    idxMcenter = 2*nGroup + 1;
    idxMtorsion = 2*nGroup + 2;

    Dm(1:nHalf,1:nHalf) = sqrt(scale(idxMcenter))*eye(nHalf);
    Dm(nHalf+1:end,nHalf+1:end) = sqrt(scale(idxMtorsion))*eye(nHalf);

    KqNew = Dk * Kq * Dk;
    MqNew = Dm * Mq * Dm;

    Knew = T' * KqNew * T;
    Mnew = T' * MqNew * T;

    Knew = 0.5*(Knew + Knew');
    Mnew = 0.5*(Mnew + Mnew');
end

function [Mnew, Knew] = apply_basic_center_torsion_scaling(M, K, T, Tinv, scale)
    % scale = [K_center K_torsion M_center M_torsion]

    if length(scale) < 4
        error('scale must have at least 4 values: [K_center K_torsion M_center M_torsion].');
    end

    kCenter  = scale(1);
    kTorsion = scale(2);
    mCenter  = scale(3);
    mTorsion = scale(4);

    n = size(M,1);
    nHalf = n/2;

    Kq = Tinv' * K * Tinv;
    Mq = Tinv' * M * Tinv;

    Dk = eye(n);
    Dm = eye(n);

    Dk(1:nHalf,1:nHalf) = sqrt(kCenter)*eye(nHalf);
    Dk(nHalf+1:end,nHalf+1:end) = sqrt(kTorsion)*eye(nHalf);

    Dm(1:nHalf,1:nHalf) = sqrt(mCenter)*eye(nHalf);
    Dm(nHalf+1:end,nHalf+1:end) = sqrt(mTorsion)*eye(nHalf);

    KqNew = Dk * Kq * Dk;
    MqNew = Dm * Mq * Dm;

    Knew = T' * KqNew * T;
    Mnew = T' * MqNew * T;

    Knew = 0.5*(Knew + Knew');
    Mnew = 0.5*(Mnew + Mnew');
end

function J = objective_frequency_update_v7_merged(x, M0, K0, T, Tinv, groupStation, expFreqHz, expPhi, respFE, refFE, ...
    useReferenceRatio, nCalcMode, nUseMode, modeMatchMethod, torsion_mode_idx, torsionModeWeight, w_freq, w_mac, w_reg, w_maxerr)

    scale = exp(x(:));

    try
        [Mtry, Ktry] = apply_group_center_torsion_scaling(M0, K0, T, Tinv, groupStation, scale);
        [freqTry, PhiTry] = modal_analysis_MK(Mtry, Ktry, nCalcMode);
    catch
        J = 1e12;
        return;
    end

    if strcmpi(modeMatchMethod, 'ordered_frequency_only')
        freqMatch = freqTry(1:nUseMode);
        macDiag = nan(nUseMode,1);
    else
        PhiTry = normalize_columns(PhiTry);
        PhiObsTry = fe_modes_to_observation_modes(PhiTry, respFE, refFE, useReferenceRatio);
        PhiObsTry = normalize_columns(PhiObsTry);

        [~, freqMatch, ~, macDiag, ~] = match_modes(expFreqHz, expPhi, freqTry, PhiObsTry, modeMatchMethod);
    end

    freqError = (freqMatch(:) - expFreqHz(:)) ./ expFreqHz(:);

    modeWeight = ones(nUseMode,1);
    idxT = torsion_mode_idx(torsion_mode_idx <= nUseMode);
    modeWeight(idxT) = torsionModeWeight;

    J_freq = sum(modeWeight .* freqError.^2);
    J_max = max(abs(freqError))^2;
    J_reg  = sum(log(scale(:)).^2);

    if strcmpi(modeMatchMethod, 'ordered_frequency_only') || all(isnan(macDiag))
        J_mac = 0;
    else
        J_mac = sum(modeWeight .* (1 - macDiag(:)).^2);
    end

    J = w_freq*J_freq + w_mac*J_mac + w_reg*J_reg + w_maxerr*J_max;

    if ~isfinite(J)
        J = 1e12;
    end
end

function x = bound_transform(y, lb, ub)
    s = 1 ./ (1 + exp(-y(:)));
    x = lb(:) + (ub(:)-lb(:)).*s;
end

function [Mup, Kup, scaleOpt, updateSource] = load_updated_MK_or_scale_merged(M0, K0, pairFE, groupStation)
    scaleOpt = [];

    resultCandidates = { ...
        'hangduri_24node_merged_result.mat', ...
        'haduri_v7_result.mat', ...
        'haduri_v7_result(1).mat', ...
        'haduri_freq_mac_result.mat', ...
        'haduri_freq_mac_result(1).mat', ...
        'frequency_only_result.mat', ...
        'hangduri_updated_state_space_model.mat'};

    for i = 1:length(resultCandidates)
        f = resultCandidates{i};

        if exist(f, 'file') == 2
            S = load(f);

            if isfield(S, 'Mup') && isfield(S, 'Kup')
                Mup = S.Mup;
                Kup = S.Kup;

                if isfield(S, 'scaleOpt')
                    scaleOpt = S.scaleOpt;
                end

                updateSource = sprintf('Loaded Mup, Kup directly from %s', f);
                return;
            end

            if isfield(S, 'scaleOpt')
                scaleOpt = S.scaleOpt(:);
                T = build_center_torsion_transform(pairFE, size(M0,1));
                Tinv = inv(T);

                if length(scaleOpt) == 10
                    [Mup, Kup] = apply_group_center_torsion_scaling(M0, K0, T, Tinv, groupStation, scaleOpt);
                elseif length(scaleOpt) == 4
                    [Mup, Kup] = apply_basic_center_torsion_scaling(M0, K0, T, Tinv, scaleOpt);
                else
                    error('Unsupported scaleOpt length in %s: %d', f, length(scaleOpt));
                end

                updateSource = sprintf('Loaded scaleOpt from %s and applied to original M,K', f);
                return;
            end
        end
    end

    paramCandidates = { ...
        'hangduri_24node_merged_parameter_table.xlsx', ...
        'haduri_v7_parameter_table.xlsx', ...
        'haduri_v7_parameter_table(1).xlsx', ...
        'haduri_freq_mac_parameter_table.xlsx', ...
        'haduri_freq_mac_parameter_table(1).xlsx', ...
        'frequency_parameter_table.xlsx'};

    for i = 1:length(paramCandidates)
        f = paramCandidates{i};

        if exist(f, 'file') == 2
            scaleOpt = read_scale_from_parameter_table(f);
            T = build_center_torsion_transform(pairFE, size(M0,1));
            Tinv = inv(T);

            if length(scaleOpt) == 10
                [Mup, Kup] = apply_group_center_torsion_scaling(M0, K0, T, Tinv, groupStation, scaleOpt);
            elseif length(scaleOpt) == 4
                [Mup, Kup] = apply_basic_center_torsion_scaling(M0, K0, T, Tinv, scaleOpt);
            else
                error('Unsupported scaleOpt length from parameter table %s: %d', f, length(scaleOpt));
            end

            updateSource = sprintf('Loaded scale parameters from %s and applied to original M,K', f);
            return;
        end
    end

    error(['No updated result file or parameter table was found. ', ...
           'Set runUpdating = true, or provide haduri_v7_result.mat / parameter table.']);
end

function scaleOpt = read_scale_from_parameter_table(filename)
    try
        P = readtable(filename, 'Sheet', 'Scale');
    catch
        P = readtable(filename);
    end

    names = P.Properties.VariableNames;

    if any(strcmpi(names, 'Scale'))
        scaleOpt = P.Scale;
        scaleOpt = double(scaleOpt(:));
        scaleOpt = scaleOpt(isfinite(scaleOpt));
        return;
    end

    scale10names = {'Kc_G1','Kc_G2','Kc_G3','Kc_G4','Kt_G1','Kt_G2','Kt_G3','Kt_G4','M_center','M_torsion'};
    scale4names = {'K_center_scale','K_torsion_scale','M_center_scale','M_torsion_scale'};

    scale10 = nan(10,1);
    for i = 1:10
        scale10(i) = read_first_matching_value(P, names, {scale10names{i}});
    end

    if all(isfinite(scale10))
        scaleOpt = scale10;
        return;
    end

    scale4 = nan(4,1);
    for i = 1:4
        scale4(i) = read_first_matching_value(P, names, {scale4names{i}});
    end

    if all(isfinite(scale4))
        scaleOpt = scale4;
        return;
    end

    error('Could not read scale parameters from %s.', filename);
end

function val = read_first_matching_value(P, names, candidates)
    val = nan;

    for i = 1:length(candidates)
        idx = find(strcmpi(names, candidates{i}), 1);

        if ~isempty(idx)
            x = P{1,idx};

            if iscell(x)
                x = x{1};
            end

            if isstring(x) || ischar(x)
                x = str2double(x);
            end

            val = double(x);
            return;
        end
    end
end

function modeType = classify_modes_center_torsion(Phi, pairFE)
    nMode = size(Phi,2);
    Type = strings(nMode,1);
    BendingIndex = zeros(nMode,1);
    TorsionIndex = zeros(nMode,1);

    for k = 1:nMode
        phi = Phi(:,k);
        left = phi(pairFE(:,1));
        right = phi(pairFE(:,2));

        bendDen = norm(left + right) + eps;
        torsDen = norm(left - right) + eps;

        BendingIndex(k) = norm(left - right)/bendDen;
        TorsionIndex(k) = norm(left + right)/torsDen;

        if BendingIndex(k) < TorsionIndex(k)
            Type(k) = "bending-dominant";
        else
            Type(k) = "torsion-dominant";
        end
    end

    modeType = table((1:nMode).', Type, BendingIndex, TorsionIndex, ...
        'VariableNames', {'Mode','Type','BendingIndex','TorsionIndex'});
end

function [C, alpha, beta] = build_rayleigh_damping(M, K, f1, f2, zeta)
    if f1 <= 0 || f2 <= 0 || abs(f2-f1) < eps
        warning('Invalid frequencies for Rayleigh damping. Using small mass proportional damping.');
        alpha = 1e-4;
        beta = 0;
        C = alpha*M;
        return;
    end

    w1 = 2*pi*f1;
    w2 = 2*pi*f2;

    A = [1/(2*w1), w1/2;
         1/(2*w2), w2/2];

    ab = A \ [zeta; zeta];

    alpha = ab(1);
    beta = ab(2);

    C = alpha*M + beta*K;
    C = 0.5*(C + C.');
end

function [A, B, Cout, D] = build_state_space(M, C, K)
    n = size(M,1);

    Z = zeros(n);
    I = eye(n);

    A = [Z, I;
        -(M\K), -(M\C)];

    B = [Z;
         M\eye(n)];

    Cout = [I, Z];
    D = zeros(n,n);
end

function [centerResp, torsionResp] = compute_center_torsion_response(y, pairFE, deck_width)
    nT = size(y,1);
    nPair = size(pairFE,1);

    centerResp = zeros(nT,nPair);
    torsionResp = zeros(nT,nPair);

    for i = 1:nPair
        L = pairFE(i,1);
        R = pairFE(i,2);

        wL = y(:,L);
        wR = y(:,R);

        centerResp(:,i) = 0.5*(wL + wR);
        torsionResp(:,i) = (wL - wR)/deck_width;
    end
end
