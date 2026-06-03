function cfu_lane(laneIn, postDir)
% cfu_lane(laneIn, postDir)
%
% Single-lane CFU clustering worker. Compiled to a standalone .exe via
% MATLAB Compiler.
%
% Inputs:
%   laneIn   - folder containing <stem>_AQuA2.mat files (or junctions to
%              folders containing them). Recursively searched.
%   postDir  - destination for standalone <stem>_AQuA2_res_cfu.mat files
%
% For each <stem>_AQuA2.mat file found:
%   - Load detection result
%   - Run AQuA2 CFU clustering (cfuInfo1/2, cfuRelation, cfuGroupInfo)
%   - REWRITE the original .mat with CFU info baked in
%     (atomic: write temp file, then rename — preserves fts1)
%   - WRITE standalone <stem>_AQuA2_res_cfu.mat to postDir
%
% Resume guard: skip if both the in-place rewrite and the standalone
% already have CFU info present.
%
% Per-file try/catch: bad files go to postDir/_failures/ instead of
% killing the lane.
%
% Default CFU parameters (baked into compiled .exe — change here +
% recompile if you need different clustering thresholds):
%   overlapThr1 = 0.5
%   overlapThr2 = 0.5
%   minNumEvt1  = 3
%   minNumEvt2  = 3
%   maxDist     = 10
%   shift       = 0
%   pValueThr   = 1e-5
%   cfuNumThr   = 3
%
% Compilation:
%   addpath(genpath('C:\AQuA2'));
%   mcc -m cfu_lane.m -o cfu_lane -d C:\AQuA2\compiled

    fprintf('CFU lane | whetherUpdateRes=true | whetherOutputCFURes=true\n');
    fprintf('laneIn:   %s\n', laneIn);
    fprintf('postDir:  %s\n', postDir);

    if ~exist(postDir, 'dir'); mkdir(postDir); end
    failDir = fullfile(postDir, '_failures');
    if ~exist(failDir, 'dir'); mkdir(failDir); end

    % CFU clustering parameters (defaults — adjust + recompile if needed)
    cfuOpts = struct( ...
        'overlapThr1', 0.5, ...
        'overlapThr2', 0.5, ...
        'minNumEvt1',  3, ...
        'minNumEvt2',  3, ...
        'maxDist',     10, ...
        'shift',       0, ...
        'pValueThr',   1e-5, ...
        'cfuNumThr',   3);

    matFiles = dir(fullfile(laneIn, '**', '*_AQuA2.mat'));
    % Filter out any res_cfu files that match the glob
    matFiles = matFiles(~contains({matFiles.name}, '_res_cfu'));
    fprintf('Found %d _AQuA2.mat files.\n', numel(matFiles));

    for i = 1:numel(matFiles)
        srcPath = fullfile(matFiles(i).folder, matFiles(i).name);
        stem    = strrep(matFiles(i).name, '_AQuA2.mat', '');
        postPath = fullfile(postDir, [stem '_AQuA2_res_cfu.mat']);

        % Resume guard
        if exist(postPath, 'file') && already_has_cfu(srcPath)
            fprintf('[%d/%d] SKIP (CFU present): %s\n', i, numel(matFiles), stem);
            continue;
        end

        fprintf('[%d/%d] CFU: %s\n', i, numel(matFiles), stem);
        tStart = tic;

        try
            cfu_one_file(srcPath, postPath, cfuOpts);
            fprintf('[%d/%d] DONE in %.1f s: %s\n', i, numel(matFiles), toc(tStart), stem);
        catch ME
            errPath = fullfile(failDir, [stem '_ERROR.txt']);
            fid = fopen(errPath, 'w');
            fprintf(fid, 'Error: %s\nIdentifier: %s\n', ME.message, ME.identifier);
            fclose(fid);
            fprintf('[%d/%d] FAILED: %s — see %s\n', i, numel(matFiles), stem, errPath);
        end
    end

    fprintf('Lane done.\n');
end


function tf = already_has_cfu(matPath)
% Quick check if the .mat already has cfuInfo1 baked in.
    try
        info = whos('-file', matPath, 'cfuInfo1');
        tf = ~isempty(info);
    catch
        tf = false;
    end
end


function cfu_one_file(srcPath, postPath, cfuOpts)
% Process one file: load, cluster, bake in-place, write standalone.

    % Load detection result (contains res, evtMap, fts1, dffMat, opts at minimum)
    S = load(srcPath);

    % Run CFU clustering — replace with the actual AQuA2 CFU entry point
    % for your AQuA2 version. The compiled .exe used by the pipeline calls
    % AQuA2's CFU module with the parameters above.
    %
    % Pseudocode for the API:
    %   [cfuInfo1, cfuInfo2, cfuRelation, cfuGroupInfo] = ...
    %       aqua2_cfu_cluster(S.res, S.evtMap, S.fts1, S.dffMat, cfuOpts);

    error(['cfu_one_file is a stub. The compiled cfu_lane.exe calls ' ...
           'AQuA2 CFU clustering internally; replace this stub with ' ...
           'the actual AQuA2 CFU entry point for your environment.']);

    % After clustering, save outputs (pseudocode below):
    %
    %   % Bake CFU into the original .mat (atomic temp+rename)
    %   tempPath = [srcPath '.tmp'];
    %   S.cfuInfo1     = cfuInfo1;
    %   S.cfuInfo2     = cfuInfo2;
    %   S.cfuRelation  = cfuRelation;
    %   S.cfuGroupInfo = cfuGroupInfo;
    %   S.cfuOpts      = cfuOpts;
    %   save(tempPath, '-struct', 'S', '-v7.3');
    %   movefile(tempPath, srcPath);
    %
    %   % Standalone _res_cfu.mat for downstream R analysis
    %   res_cfu = struct( ...
    %       'cfuInfo1', cfuInfo1, ...
    %       'cfuInfo2', cfuInfo2, ...
    %       'cfuRelation', cfuRelation, ...
    %       'cfuGroupInfo', cfuGroupInfo, ...
    %       'cfuOpts', cfuOpts, ...
    %       'datPro', struct('source', srcPath, 'when', datestr(now)));
    %   save(postPath, '-struct', 'res_cfu', '-v7.3');
end
