function run = main(dataDir, outputDir)
% Run the three Gunja Station experiments. See docs/실행방법.md for CSV inputs.
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root,'src'));
if nargin < 1 || isempty(dataDir)
    dataDir = fullfile(root,'data','demo');
end
if nargin < 2 || isempty(outputDir)
    [~,dataset] = fileparts(regexprep(char(dataDir),'[/\\]+$',''));
    outputDir = fullfile(root,'results',dataset);
end
cfg = simulationConfig();
map = loadGunjaMap(dataDir,cfg);
plan = chooseAddedSites(map,cfg);
fprintf('%s\n',map.label);
fprintf('Added sites: %s and %s (planning at 28 GHz / 800 MHz)\n', ...
    map.siteId{plan.added(1)},map.siteId{plan.added(2)});

layouts = {[],plan.added};
lastFrequency = NaN;
results = cell(numel(cfg.bands),numel(layouts));
for b = 1:numel(cfg.bands)
    band = cfg.bands(b);
    if band.frequencyGHz ~= lastFrequency
        power = receivedPower(map,cfg,band.frequencyGHz,cfg.evaluationTrials,cfg.evaluationSeed);
        lastFrequency = band.frequencyGHz;
    end
    for layout = 1:numel(layouts)
        results{b,layout} = simulateNetwork(power,map,layouts{layout},band.bandwidthMHz,cfg.noiseFigureDb);
    end
end

if ~isfolder(outputDir)
    [ok,msg] = mkdir(outputDir);
    if ~ok, error('gunja:output','%s',msg); end
end
writeResults(outputDir,map,cfg,plan,results);
plotResults(outputDir,map,cfg,plan,results);
fprintf('Results: %s\n',outputDir);
if nargout > 0
    run = struct('outputDir',outputDir,'selectedSites',{map.siteId(plan.added)}, ...
        'configuration',cfg,'results',{results});
end
end
