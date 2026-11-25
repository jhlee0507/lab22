function cfg = simulationConfig()
% Ground-level pedestrian in the 3GPP TR 38.901 urban macro (UMa) scenario.
cfg.eastLimitsM = [-300, 300];
cfg.northLimitsM = [-300, 300];
cfg.gridStepM = 10;
cfg.bsHeightM = 25;
cfg.ueHeightM = 1.5;
cfg.sectorTxDbm = 43;       % Total conducted power per sector across the band
cfg.noiseFigureDb = 7;
cfg.peakGainDbi = 8;
cfg.downtiltDeg = 10;
cfg.planningSeed = 4107;
cfg.evaluationSeed = 9713;
cfg.planningTrials = 8;
cfg.evaluationTrials = 20;
cfg.sinrColorLimitsDb = [-20, 25];
cfg.bands = struct('id', {'f35_b100','f28_b100','f28_b800'}, ...
    'frequencyGHz', {3.5,28,28}, 'bandwidthMHz', {100,100,800});
end
