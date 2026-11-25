function power = receivedPower(map, cfg, fcGHz, nTrials, seed)
% UMa large-scale downlink power. Rows run over grid points, then trials.
% Compute every candidate once so changing the active sites preserves links.
if fcGHz <= 0.5 || fcGHz > 100 || cfg.bsHeightM ~= 25 || cfg.ueHeightM < 1.5 || cfg.ueHeightM >= 13
    error('gunja:uma', 'This UMa implementation uses 0.5 < f <= 100 GHz, BS 25 m and UE 1.5 to <13 m.');
end
previousRng = rng;
restoreRng = onCleanup(@() rng(previousRng)); %#ok<NASGU>
rng(seed, 'twister');
power.nPoints = size(map.xy,1);
power.nTrials = nTrials;
nSites = size(map.siteXY,1);
power.strongestMw = zeros(power.nPoints*nTrials,nSites);
power.totalMw = zeros(power.nPoints*nTrials,nSites);

% Table 7.4.3-2: indoor depth and penetration variation are UE-specific.
depthM = map.indoor .* (25 * min(rand(power.nPoints,nTrials),rand(power.nPoints,nTrials)));
glassDb = 2 + 0.2*fcGHz;
concreteDb = 5 + 4*fcGHz;
wallDb = 5 - 10*log10(0.3*10^(-glassDb/10) + 0.7*10^(-concreteDb/10));
o2iDb = map.indoor .* (wallDb + 0.5*depthM + 4.4*randn(power.nPoints,nTrials));

heightDiffM = cfg.bsHeightM - cfg.ueHeightM;
% Table 7.4.1-1: hE=1 m for a low UE, Hz in the breakpoint, GHz in PL.
breakM = 4*(cfg.bsHeightM-1)*(cfg.ueHeightM-1)*(fcGHz*1e9)/3e8;
for s = 1:nSites
    east = map.xy(:,1) - map.siteXY(s,1);
    north = map.xy(:,2) - map.siteXY(s,2);
    horizontalM = hypot(east,north);
    if any(horizontalM > 5000)
        error('gunja:range', 'Site %s exceeds the 5 km UMa path-loss range.', map.siteId{s});
    end
    modelDistM = max(horizontalM,10);   % Extend the 10 m boundary value inwards.
    dist3dM = hypot(modelDistM,heightDiffM);
    losDb = 28 + 22*log10(dist3dM) + 20*log10(fcGHz);
    far = modelDistM > breakM;
    losDb(far) = 28 + 40*log10(dist3dM(far)) + 20*log10(fcGHz) ...
        - 9*log10(breakM^2 + heightDiffM^2);
    nlosDb = max(losDb,13.54 + 39.08*log10(dist3dM) + 20*log10(fcGHz) ...
        - 0.6*(cfg.ueHeightM-1.5));

    % Table 7.4.2-1. Approximate the exterior portion of each indoor link.
    outdoorM = max(horizontalM-depthM,18);
    pLos = 18./outdoorM + (1-18./outdoorM).*exp(-outdoorM/63);
    isLos = rand(power.nPoints,nTrials) < pLos;
    pathLossDb = nlosDb + isLos.*(losDb-nlosDb);
    shadowDb = (6-2*isLos).*randn(power.nPoints,nTrials);  % 4 dB LOS, 6 dB NLOS
    linkMw = 10.^((cfg.sectorTxDbm - pathLossDb - shadowDb - o2iDb)/10);

    % Same site propagation for three sectors, independent directional gains.
    bearing = atan2d(east,north);
    boresights = map.azimuthDeg(s) + [0,120,240];
    angle = mod(bearing-boresights+180,360)-180;
    horizontalLoss = min(12*(angle/65).^2,30);
    downAngle = atan2d(heightDiffM,horizontalM);
    verticalLoss = min(12*((downAngle-cfg.downtiltDeg)/65).^2,30);
    gainLin = 10.^((cfg.peakGainDbi-min(horizontalLoss+verticalLoss,30))/10);
    strongest = linkMw .* max(gainLin,[],2);
    total = linkMw .* sum(gainLin,2);
    power.strongestMw(:,s) = strongest(:);
    power.totalMw(:,s) = total(:);
end
end
