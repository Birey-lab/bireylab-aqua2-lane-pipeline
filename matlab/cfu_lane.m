function cfu_lane(pIn, pOut)
% CFU_LANE  Headless, compiled CFU batch worker for one lane.
%   cfu_lane(pIn, pOut)
%     pIn  : a lane folder whose *_AQuA2.mat files (searched recursively) this
%            lane should process. (We pass a folder that CONTAINS the per-file
%            result folders for this lane — see Build-CFU-Lanes.ps1.)
%     pOut : the common POST output folder for standalone *_res_cfu.mat files.
%
% Behaviour (mirrors CFU_cmd_batch.m logic, both output flags ON):
%   - whetherUpdateRes   = true  -> bake cfu fields into the original _AQuA2.mat
%                                   (ATOMIC: temp file + rename; never corrupts).
%   - whetherOutputCFURes= true  -> write standalone _res_cfu.mat to pOut.
%   - single/dual channel auto-detected from res.opts.singleChannel.
%   - parpool auto-create disabled so the cfu parfors run SERIALLY
%     (correct under file-level parallelism; avoids 20x oversubscription).
%   - resume guard: skip a file if its _res_cfu.mat already exists in pOut.
%   - per-file try/catch: failures logged to pOut\_failures\<name>_ERROR.txt,
%     loop continues.

    fprintf('cfu_lane v1 (2026-05-25): parpool=disabled, updateRes=ON(atomic), outputCFU=ON, resume+guard=ON\n');

    % --- normalise args ---
    if nargin < 2 || isempty(pIn) || isempty(pOut)
        error('cfu_lane:args','Usage: cfu_lane(pIn, pOut)');
    end
    if endsWith(pOut, filesep), pOut = pOut(1:end-1); end
    if ~exist(pOut, 'dir'), mkdir(pOut); end
    failDir = fullfile(pOut, '_failures');
    if ~exist(failDir, 'dir'), mkdir(failDir); end

    % --- init AQuA2 paths ---
    startup;

    % --- disable parallel pool auto-create (parfor -> serial) ---
    try
        ps = parallel.Settings;
        ps.Pool.AutoCreate = false;
    catch
        % PCT not installed: parfor already runs serially. Fine.
    end

    % --- CFU options (defaults from CFU_cmd_batch.m) ---
    cfuOpts.cfuDetect.overlapThr1 = 0.5;
    cfuOpts.cfuDetect.overlapThr2 = 0.5;
    cfuOpts.cfuDetect.minNumEvt1  = 3;
    cfuOpts.cfuDetect.minNumEvt2  = 3;
    cfuOpts.cfuAnalysis.maxDist   = 10;
    cfuOpts.cfuAnalysis.shift     = 0;
    cfuOpts.cfuGroup.pValueThr    = 1e-5;
    cfuOpts.cfuGroup.cfuNumThr    = 3;

    % --- find this lane's files (recursive, like CFU_cmd_batch dir(**)) ---
    files = dir(fullfile(pIn, '**', '*_AQuA2.mat'));
    % exclude anything that is itself a cfu result, just in case
    keep = ~endsWith({files.name}, '_res_cfu.mat');
    files = files(keep);
    nF = numel(files);
    fprintf('Lane input: %s\n', pIn);
    fprintf('Found %d _AQuA2.mat files.\n', nF);

    for xxx = 1:nF
        f1       = files(xxx).name;             % <stem>_AQuA2.mat
        filepath = files(xxx).folder;
        stem     = f1(1:end-4);                 % <stem>_AQuA2
        inPath   = fullfile(filepath, f1);
        outCfu   = fullfile(pOut, [stem, '_res_cfu.mat']);

        % resume guard: standalone output already exists -> skip
        if exist(outCfu, 'file')
            fprintf('[%d/%d] SKIP (done): %s\n', xxx, nF, f1);
            continue;
        end

        tFile = tic;
        try
            S = load(inPath);          % loads variable 'res'
            res = S.res; clear S;

            % --- CFU detect ---
            [cfuInfo1, cfuInfo2] = cfu.CFUdetectScript(res, cfuOpts);
            nCFU = size(cfuInfo1, 1);

            % --- dependency + grouping ---
            cfuRelation  = cfu.calAllDependencyScript(cfuInfo1, cfuInfo2, cfuOpts);
            cfuGroupInfo = cfu.groupCFUscript(cfuInfo1, cfuInfo2, cfuRelation, cfuOpts);

            % --- whetherOutputCFURes = true : standalone _res_cfu.mat to POST ---
            datPro = util.normalize01(mean(single(res.datOrg1), 4)); %#ok<NASGU>
            % atomic write of standalone too (temp + rename)
            tmpCfu = [outCfu, '.tmp'];
            save(tmpCfu, 'cfuInfo1','cfuInfo2','cfuRelation','cfuGroupInfo','cfuOpts','datPro', ...
                 '-v7.3','-nocompression');
            if exist(outCfu,'file'), delete(outCfu); end
            movefile(tmpCfu, outCfu, 'f');

            % --- whetherUpdateRes = true : bake into original _AQuA2.mat ATOMICALLY ---
            res.cfuInfo1     = cfuInfo1;
            res.cfuInfo2     = cfuInfo2;
            res.cfuRelation  = cfuRelation;
            res.cfuGroupInfo = cfuGroupInfo;
            tmpIn = [inPath, '.tmp'];
            save(tmpIn, 'res', '-v7.3', '-nocompression');   % match part-1 save flags
            % atomic replace: only overwrites original AFTER temp fully written
            movefile(tmpIn, inPath, 'f');

            fprintf('[%d/%d] DONE %s | nCFU=%d | %.1fs\n', xxx, nF, f1, nCFU, toc(tFile));
            clear res cfuInfo1 cfuInfo2 cfuRelation cfuGroupInfo datPro;

        catch ME
            % clean any stray temp files so a half-write never lingers
            tmpIn  = [inPath, '.tmp']; if exist(tmpIn,'file'),  delete(tmpIn);  end
            tmpCfu = [outCfu, '.tmp']; if exist(tmpCfu,'file'), delete(tmpCfu); end
            errFile = fullfile(failDir, [stem, '_ERROR.txt']);
            fid = fopen(errFile, 'w');
            if fid > 0
                fprintf(fid, 'File: %s\n', inPath);
                fprintf(fid, 'Time: %s\n', datestr(now));
                fprintf(fid, 'Error: %s\n', ME.message);
                for k = 1:numel(ME.stack)
                    fprintf(fid, '  at %s (line %d)\n', ME.stack(k).name, ME.stack(k).line);
                end
                fclose(fid);
            end
            fprintf('[%d/%d] FAIL %s | %s\n', xxx, nF, f1, ME.message);
        end
    end

    fprintf('Lane complete: %s\n', pIn);
end
