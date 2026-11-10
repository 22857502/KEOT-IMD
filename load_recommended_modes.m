function [modeIdx, modeFreq, nNeeded] = load_recommended_modes(matFile, varargin)
%LOAD_RECOMMENDED_MODES mode_selection_basis.m 결과(mode_selection_result.mat)에서
%   EOT용 target mode 목록을 불러온다.
%
%   [modeIdx, modeFreq, nNeeded] = LOAD_RECOMMENDED_MODES(matFile, Name,Value,...)
%
%   mode_selection_basis.m이 저장한 mode_selection_result.mat에는
%       mode_freq        : 전체 후보 모드 주파수 [Hz]
%       recommendedModes : 누적에너지 임계값(energyThreshold)을 만족하는
%                          최소 모드 세트 (원 모드 번호, mode_freq 기준)
%       nNeeded          : 그 모드 개수
%   가 들어있다. 이 함수는 이를 그대로 읽어 EOT 스크립트의
%   no_mode / target mode 목록으로 바로 쓸 수 있게 반환한다.
%
%   INPUT
%       matFile : 'mode_selection_result.mat' 경로
%
%   Name-Value (선택)
%       'Override' : 자동추천 대신 모드 번호를 직접 지정하고 싶을 때
%                    (예: [1 2 3 5]) 지정 시 .mat 파일은 무시하고 이 값을 그대로 반환.
%                    민감도 분석(자동추천 vs 수동선정 비교) 등에 사용.
%
%   OUTPUT
%       modeIdx  : 추천 모드의 원 번호 (오름차순)
%       modeFreq : 해당 모드의 주파수 [Hz] (Override 사용 시 빈 배열)
%       nNeeded  : 모드 개수 (= EOT의 no_mode로 사용)

    p = inputParser;
    addParameter(p, 'Override', []);
    parse(p, varargin{:});
    override = p.Results.Override;

    if ~isempty(override)
        modeIdx  = sort(override(:))';
        nNeeded  = numel(modeIdx);
        modeFreq = [];
        fprintf('[load_recommended_modes] Override 사용: %s (자동추천 대신 수동 지정)\n', ...
            mat2str(modeIdx));
        return;
    end

    if exist(matFile, 'file') ~= 2
        error('load_recommended_modes:fileNotFound', ...
            '%s 를 찾을 수 없습니다. mode_selection_basis.m을 먼저 실행하세요.', matFile);
    end

    S = load(matFile, 'recommendedModes', 'mode_freq', 'nNeeded');

    modeIdx  = sort(S.recommendedModes(:))';
    modeFreq = S.mode_freq(modeIdx);
    nNeeded  = S.nNeeded;

    fprintf('[load_recommended_modes] %s 로드 완료: %d개 모드 %s (%.3f~%.3f Hz)\n', ...
        matFile, nNeeded, mat2str(modeIdx), min(modeFreq), max(modeFreq));
end
