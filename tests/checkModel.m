function checkModel()
% Run from the repository root: addpath('tests'); checkModel
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'src'));
cfg = simulationConfig();
checkLinkBudget(cfg);
checkPropagation(cfg);
checkPlacement(root,cfg);
fprintf('Passed: link budget, UMa propagation and O2I, placement and statistics.\n');
end

function checkLinkBudget(cfg)
% External sector is stronger than either service sector but cannot serve.
map.role = {'service';'external';'candidate';'service'};
power.nPoints = 1;
power.nTrials = 1;
power.strongestMw = [6,1000,2000,4]*1e-9;
power.totalMw = [9,1500,3000,8]*1e-9;
base = simulateNetwork(power,map,[],100,cfg.noiseFigureDb);
wide = simulateNetwork(power,map,[],800,cfg.noiseFigureDb);
added = simulateNetwork(power,map,3,100,cfg.noiseFigureDb);
assert(abs(base.noiseDbm+87) < 1e-12);
assert(abs(wide.noiseDbm-base.noiseDbm-10*log10(8)) < 1e-12);
noise = 10^(-87/10);
expectedBase = 6e-9 / ((9+1500+8-6)*1e-9 + noise);
expectedAdded = 2000e-9 / ((9+1500+3000+8-2000)*1e-9 + noise);
assert(abs(base.sinrDb-10*log10(expectedBase)) < 1e-10);
assert(abs(added.sinrDb-10*log10(expectedAdded)) < 1e-10);
assert(abs(base.rateMbps-100*log2(1+expectedBase)) < 1e-10);
assert(wide.sinrDb < base.sinrDb && wide.rateMbps > base.rateMbps);
end

function checkPropagation(cfg)
% At 10 m a low UMa user is always LOS. Aim the first sector at the user.
map.xy = [0,10];
map.siteId = {'S';'E'};
map.siteXY = [0,0;0,20];
map.azimuthDeg = [0;180];
map.indoor = false;
cfg.downtiltDeg = atan2d(cfg.bsHeightM-cfg.ueHeightM,10);
nTrials = 6000;
before = rng;
out35 = receivedPower(map,cfg,3.5,nTrials,31);
after = rng;
assert(isequal(before,after));
out28 = receivedPower(map,cfg,28,nTrials,31);
rx35 = 10*log10(out35.strongestMw);
rx28 = 10*log10(out28.strongestMw);
d3d = hypot(10,cfg.bsHeightM-cfg.ueHeightM);
expectedDbm = cfg.sectorTxDbm + cfg.peakGainDbi - (28+22*log10(d3d)+20*log10(3.5));
assert(abs(mean(rx35(:,1))-expectedDbm) < 0.35); % Mean of 6000 shadow draws
assert(max(abs(rx35(:)-rx28(:)-20*log10(28/3.5))) < 1e-10);

% UE penetration is common to both directions, including the interference link.
map.indoor = true;
in35 = receivedPower(map,cfg,3.5,nTrials,31);
in28 = receivedPower(map,cfg,28,nTrials,31);
loss35 = rx35-10*log10(in35.strongestMw);
loss28 = rx28-10*log10(in28.strongestMw);
assert(max(abs(loss35(:,1)-loss35(:,2))) < 1e-10);
% Low-loss glass/concrete wall: 12.70 dB at 3.5 GHz, 17.83 dB at 28 GHz.
wall = @(f) 5-10*log10(0.3*10^(-(2+0.2*f)/10)+0.7*10^(-(5+4*f)/10));
assert(max(abs(loss28(:)-loss35(:)-(wall(28)-wall(3.5)))) < 1e-10);
assert(abs(mean(loss35(:,1))-(wall(3.5)+0.5*25/3)) < 0.35);
end

function checkPlacement(root,cfg)
map = loadGunjaMap(fullfile(root,'data','demo'),cfg);
assert(size(unique(map.xy,'rows'),1) == size(map.xy,1));
assert(any(map.indoor) && any(~map.indoor));
assert(isequal(samplePercentile(1:100,[5,50]),[5,50]));
plan = chooseAddedSites(map,cfg);
n = sum(strcmp(map.role,'candidate'));
assert(size(plan.pairs,1) == n*(n-1)/2);
assert(numel(unique(plan.added)) == 2 && all(strcmp(map.role(plan.added),'candidate')));
assert(plan.rateP5(plan.best) == max(plan.rateP5));
end
