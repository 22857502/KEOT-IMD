function [Mnew, Knew] = apply_group_center_torsion_scaling(M, K, T, Tinv, groupStation, scale)
%APPLY_GROUP_CENTER_TORSION_SCALING center/torsion 좌표계에서 station 그룹별로
%   강성/질량을 스케일링 (hangduri merged 코드의 local function을 standalone으로 추출)
%
%   [Mnew, Knew] = APPLY_GROUP_CENTER_TORSION_SCALING(M, K, T, Tinv, groupStation, scale)
%
%   scale = [Kc_G1 ... Kc_Gn  Kt_G1 ... Kt_Gn  Mc  Mt]  (길이 2*nGroup + 2)
%   FE updating에서는 실측에 맞춰 이 scale을 최적화했지만, 이 함수 자체는
%   손상 시나리오 생성(강성 저감)에도 그대로 재사용 가능합니다 (apply_damage_scenario.m 참고).
%
%   INPUT
%       M, K         : nNode x nNode 원본(또는 업데이트된) 질량/강성 행렬
%       T, Tinv      : build_center_torsion_transform() 결과 및 그 역행렬
%       groupStation : station 그룹 정의 cell array (예: {1:3, 4:6, 7:9, 10:12})
%       scale        : 스케일 벡터 (1 = 변화 없음, <1 = 저감/손상, >1 = 강화)
%
%   OUTPUT
%       Mnew, Knew : 스케일링된 질량/강성 행렬 (대칭화됨)

    n = size(M,1);
    nHalf = n/2;
    nGroup = numel(groupStation);

    if length(scale) ~= 2*nGroup + 2
        error('apply_group_center_torsion_scaling:size', ...
            'scale 길이는 %d 이어야 합니다 (2*nGroup+2).', 2*nGroup + 2);
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

    idxMcenter  = 2*nGroup + 1;
    idxMtorsion = 2*nGroup + 2;
    Dm(1:nHalf,1:nHalf)         = sqrt(scale(idxMcenter))*eye(nHalf);
    Dm(nHalf+1:end,nHalf+1:end) = sqrt(scale(idxMtorsion))*eye(nHalf);

    KqNew = Dk * Kq * Dk;
    MqNew = Dm * Mq * Dm;

    Knew = T' * KqNew * T;
    Mnew = T' * MqNew * T;

    Knew = 0.5*(Knew + Knew');
    Mnew = 0.5*(Mnew + Mnew');
end
