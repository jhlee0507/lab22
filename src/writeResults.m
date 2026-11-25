function writeResults(outputDir, map, cfg, plan, results)
% Export the full evaluation and the independent planning comparison separately.
layouts = {'baseline','plus2'};
groups = {'all','indoor','outdoor'};
masks = {true(size(map.indoor)),map.indoor,~map.indoor};
[summary,closeSummary] = outputFile(outputDir,'summary.csv'); %#ok<ASGLU>
fprintf(summary,['layout,band,frequency_ghz,bandwidth_mhz,population,samples,noise_dbm,' ...
    'sinr_p50_db,rate_p5_mbps,rate_p50_mbps,rate_mean_mbps\n']);
[gridFile,closeGrid] = outputFile(outputDir,'grid_metrics.csv'); %#ok<ASGLU>
fprintf(gridFile,'layout,band,east_m,north_m,indoor,median_sinr_db,median_rate_mbps\n');
for b = 1:numel(cfg.bands)
    band = cfg.bands(b);
    for l = 1:numel(layouts)
        result = results{b,l};
        for g = 1:numel(groups)
            rates = result.rateMbps(masks{g},:);
            sinr = result.sinrDb(masks{g},:);
            pct = samplePercentile(rates,[5,50]);
            fprintf(summary,'%s,%s,%g,%g,%s,%d,%.8f,%.8f,%.8f,%.8f,%.8f\n', ...
                layouts{l},band.id,band.frequencyGHz,band.bandwidthMHz,groups{g}, ...
                numel(rates),result.noiseDbm,samplePercentile(sinr,50),pct(1),pct(2),mean(rates(:)));
        end
        rows = [map.xy,double(map.indoor),median(result.sinrDb,2),median(result.rateMbps,2)];
        rowFormat = [layouts{l} ',' band.id ',%.10g,%.10g,%d,%.8f,%.8f\n'];
        fprintf(gridFile,rowFormat,rows.');
    end
end

[scores,closeScores] = outputFile(outputDir,'placement_scores.csv'); %#ok<ASGLU>
fprintf(scores,['site1,east1_m,north1_m,site2,east2_m,north2_m,baseline_p5_mbps,' ...
    'pair_p5_mbps,p5_change_mbps,pair_p50_mbps,selected\n']);
for k = 1:size(plan.pairs,1)
    i = plan.pairs(k,1);
    j = plan.pairs(k,2);
    fprintf(scores,'%s,%.10g,%.10g,%s,%.10g,%.10g,%.8f,%.8f,%.8f,%.8f,%d\n', ...
        map.siteId{i},map.siteXY(i,1),map.siteXY(i,2),map.siteId{j}, ...
        map.siteXY(j,1),map.siteXY(j,2),plan.baselineP5,plan.rateP5(k), ...
        plan.rateP5(k)-plan.baselineP5,plan.rateP50(k),k==plan.best);
end
[info,closeInfo] = outputFile(outputDir,'run_info.txt'); %#ok<ASGLU>
fprintf(info,'%s\nGrid: %d points (%d indoor), step %g m\n', ...
    map.label,size(map.xy,1),nnz(map.indoor),cfg.gridStepM);
fprintf(info,'Planning: %d trials, seed %d\nEvaluation: %d trials, seed %d\n', ...
    cfg.planningTrials,cfg.planningSeed,cfg.evaluationTrials,cfg.evaluationSeed);
fprintf(info,'Added: %s, %s\n',map.siteId{plan.added(1)},map.siteId{plan.added(2)});
end

function [fid,guard] = outputFile(outputDir,name)
[fid,msg] = fopen(fullfile(outputDir,name),'w','n','UTF-8');
if fid < 0, error('gunja:output','%s: %s',name,msg); end
guard = onCleanup(@() fclose(fid));
end
