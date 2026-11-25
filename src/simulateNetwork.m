function result = simulateNetwork(power, map, added, bandwidthMHz, noiseFigureDb)
% Associate with the strongest eligible sector. All other active sectors interfere.
if ~all(strcmp(map.role(added),'candidate'))
    error('gunja:addition','Only candidate sites can be added.');
end
serves = strcmp(map.role,'service');
serves(added) = true;
active = serves | strcmp(map.role,'external');
signalMw = max(power.strongestMw(:,serves),[],2);
interferenceMw = max(0,sum(power.totalMw(:,active),2)-signalMw);
bandwidthHz = bandwidthMHz*1e6;
result.noiseDbm = -174 + 10*log10(bandwidthHz) + noiseFigureDb;
noiseMw = 10^(result.noiseDbm/10);
sinr = signalMw ./ (interferenceMw+noiseMw);
result.sinrDb = reshape(10*log10(sinr),power.nPoints,power.nTrials);
result.rateMbps = reshape(bandwidthHz*log1p(sinr)/log(2)/1e6,power.nPoints,power.nTrials);
end
