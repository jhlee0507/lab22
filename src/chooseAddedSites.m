function plan = chooseAddedSites(map, cfg)
% Compare pairs at 28 GHz / 800 MHz on planning trials. Evaluation uses a new seed.
band = cfg.bands(3);
power = receivedPower(map,cfg,band.frequencyGHz,cfg.planningTrials,cfg.planningSeed);
base = simulateNetwork(power,map,[],band.bandwidthMHz,cfg.noiseFigureDb);
plan.baselineP5 = samplePercentile(base.rateMbps,5);
candidates = find(strcmp(map.role,'candidate'));
plan.pairs = nchoosek(candidates(:).',2);
nPairs = size(plan.pairs,1);
plan.rateP5 = zeros(nPairs,1);
plan.rateP50 = zeros(nPairs,1);
for k = 1:nPairs
    candidate = simulateNetwork(power,map,plan.pairs(k,:),band.bandwidthMHz,cfg.noiseFigureDb);
    rates = samplePercentile(candidate.rateMbps,[5,50]);
    plan.rateP5(k) = rates(1);
    plan.rateP50(k) = rates(2);
end
% Maximize the fifth percentile; break ties by median, then CSV order.
[~,order] = sortrows([-plan.rateP5,-plan.rateP50,(1:nPairs)'],[1,2,3]);
plan.best = order(1);
plan.added = plan.pairs(plan.best,:);
end
