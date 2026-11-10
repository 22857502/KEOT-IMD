function T = build_center_torsion_transform(pairFE, nNode)
%BUILD_CENTER_TORSION_TRANSFORM center/torsion 좌표변환 행렬 생성
%   (hangduri_24node_..._merged_final.m의 local function을 재사용 가능하도록
%    standalone 함수로 추출한 버전. 로직은 원본과 동일.)
%
%   T = BUILD_CENTER_TORSION_TRANSFORM(pairFE, nNode)
%
%   q_center = (w_L + w_R)/2, q_torsion = (w_L - w_R)/2 로 변환하는 행렬.
%   q = T*w  (w: 원래 FE 좌표, q: center/torsion 좌표)
%
%   INPUT
%       pairFE : nPair x 2, 좌/우 FE node 쌍 (예: [(1:12)', (13:24)'])
%       nNode  : 전체 FE node 수 (예: 24)
%
%   OUTPUT
%       T : nNode x nNode 변환행렬

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
