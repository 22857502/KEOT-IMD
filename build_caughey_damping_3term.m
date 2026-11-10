function [C, a] = build_caughey_damping_3term(M, K, freqHz, dampingRatio)
%BUILD_CAUGHEY_DAMPING_3TERM 실측 모드별 감쇠비를 이용한 3-term Caughey 감쇠행렬 생성
%
%   [C, a] = BUILD_CAUGHEY_DAMPING_3TERM(M, K, freqHz, dampingRatio)
%
%   El-Centro 원본 스니펫에서 사용한 방식과 동일:
%       C = a1*M + a2*K + a3*K*(M\K)
%   위 3개 계수를 각 모드의 (주파수, 감쇠비) 쌍에 대해 최소자승으로 추정.
%
%   선택적으로 사용: 기본 merged 파이프라인은 Rayleigh damping(C0, Cup)을
%   이미 저장하고 있으므로, 실측 Damping.xlsx(모드별 감쇠비) 데이터가 있고
%   그것을 직접 반영하고 싶을 때만 이 함수로 C0/Cup을 대체하면 됩니다.
%   Rayleigh(2-term)와 달리 3개 이상의 모드에서 감쇠비를 동시에 만족시킬 수
%   있다는 장점이 있지만, 최소자승 특성상 개별 모드에서 완전히 일치하지는
%   않을 수 있습니다.
%
%   INPUT
%       M, K         : n x n 질량/강성 행렬
%       freqHz       : m x 1 실측 고유진동수 [Hz] (m >= 3)
%       dampingRatio : m x 1 해당 모드의 실측 감쇠비 (예: Damping.xlsx)
%
%   OUTPUT
%       C : n x n 감쇠행렬 (대칭화됨)
%       a : 3 x 1 추정계수 [a1;a2;a3]

    freqHz = freqHz(:);
    dampingRatio = dampingRatio(:);

    if length(freqHz) ~= length(dampingRatio)
        error('build_caughey_damping_3term:size', ...
            'freqHz와 dampingRatio 길이가 일치해야 합니다.');
    end
    if length(freqHz) < 3
        error('build_caughey_damping_3term:tooFew', ...
            '최소 3개 이상의 모드 데이터가 필요합니다.');
    end

    w = 2*pi*freqHz;

    Amat = 2 * [1./w, w, w.^3];
    a = Amat \ dampingRatio;

    C = a(1)*M + a(2)*K + a(3)*K*(M\K);
    C = 0.5*(C + C.');
end
