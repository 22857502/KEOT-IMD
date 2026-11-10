function [A, B, Cout, D, Gamma] = build_seismic_state_space(M, C, K, outputType)
%BUILD_SEISMIC_STATE_SPACE 지반가속도 입력 기반 상태공간모델 생성
%
%   [A, B, Cout, D, Gamma] = BUILD_SEISMIC_STATE_SPACE(M, C, K, outputType)
%
%   운동방정식 (상대좌표계):
%       M*xddot_rel + C*xdot_rel + K*x_rel = -M*Gamma*ag(t)
%
%   상태벡터 z = [xdot_rel; x_rel]  (속도가 먼저, 변위가 뒤)
%   입력 u = ag(t)  (스칼라 지반가속도, 모든 DOF에 동일하게 작용한다고 가정)
%
%   Gamma = ones(n,1) : 모든 DOF가 지반과 동일한 방향/크기로 가진된다는 가정.
%           실제 지점 조건(예: 교좌장치 위치)에 따라 방향별로 0/1을 다르게
%           주는 것이 더 정확할 수 있으므로 필요시 수정할 것.
%
%   outputType:
%       'relative' : 상대가속도 xddot_rel 출력
%       'absolute' : 절대가속도 xddot_abs = xddot_rel + ag(t) 출력 (기본값)
%                    가속도계 실측값(24채널)과 직접 비교할 때는 이 옵션을 권장.
%
%       유도: y_rel = Cout*z + (-Gamma)*u = xddot_rel
%             xddot_abs = xddot_rel + Gamma*ag(t)
%                       = Cout*z + (-Gamma + Gamma)*u = Cout*z + 0*u
%             즉 Cout은 동일하고 D만 0으로 바뀜.
%
%   INPUT
%       M, C, K   : n x n 질량/감쇠/강성 행렬 (예: 한두리교 24노드 모델)
%       outputType: 'relative' 또는 'absolute' (미지정시 'absolute')
%
%   OUTPUT
%       A, B, Cout, D : 연속시간 상태공간 행렬 (2n x 2n, 2n x 1, n x 2n, n x 1)
%       Gamma         : 사용된 influence vector (n x 1)

    if nargin < 4 || isempty(outputType)
        outputType = 'absolute';
    end

    n = size(M,1);

    if size(M,1) ~= size(M,2) || size(K,1) ~= size(K,2) || size(C,1) ~= size(C,2)
        error('build_seismic_state_space:size', 'M, C, K는 모두 정방행렬이어야 합니다.');
    end
    if any(size(M) ~= size(K)) || any(size(M) ~= size(C))
        error('build_seismic_state_space:mismatch', 'M, C, K 크기가 서로 일치하지 않습니다.');
    end

    MinvC = M \ C;
    MinvK = M \ K;

    A = [ -MinvC,   -MinvK;
           eye(n),   zeros(n) ];

    Gamma = ones(n,1);   % 균일 지반가진 가정 (필요시 지점 DOF만 1로 수정)

    B = [ -Gamma;
           zeros(n,1) ];

    Cout = [ -MinvC, -MinvK ];   % n x 2n

    switch lower(outputType)
        case 'relative'
            D = -Gamma;
        case 'absolute'
            D = zeros(n,1);
        otherwise
            error('build_seismic_state_space:outputType', ...
                'outputType은 ''relative'' 또는 ''absolute''여야 합니다.');
    end

    % 안정성 체크
    lamA = eig(A);
    if any(real(lamA) > 1e-8)
        warning('build_seismic_state_space:unstable', ...
            'A행렬이 불안정합니다 (max real(eig(A)) = %.3e). M,C,K를 확인하세요.', ...
            max(real(lamA)));
    end

    if ~all(isfinite(A(:))) || ~all(isfinite(B(:))) || ...
       ~all(isfinite(Cout(:))) || ~all(isfinite(D(:)))
        error('build_seismic_state_space:nanInf', 'A,B,Cout,D 중 NaN/Inf가 있습니다.');
    end
end
