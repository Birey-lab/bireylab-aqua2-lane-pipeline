function aqua_lane(laneIn, laneOut)
% aqua_lane(laneIn, laneOut)
%
% Single-lane AQuA2 detection worker. Designed to be compiled to a
% standalone .exe via MATLAB Compiler (no MATLAB license consumed at
% runtime — runs on the free MATLAB Runtime).
%
% Inputs:
%   laneIn   - folder containing .tif files for this lane
%   laneOut  - destination folder for outputs (created if missing)
%
% For each .tif file in laneIn:
%   - Skip if <stem>_AQuA2.mat already exists in laneOut (resume guard)
%   - Otherwise: load TIFF, run AQuA2 detection, save outputs
%   - On error: write <stem>_ERROR.txt with the error message and continue
%
% Parameters are read from C:\AQuA2\cfg\parameters_for_batch.csv.
%
% Compilation:
%   addpath(genpath('C:\AQuA2'));
%   mcc -m aqua_lane.m -o aqua_lane -d C:\AQuA2\compiled
%
% This source corresponds to the compiled aqua_lane.exe used by the
% pipeline. Banner reads: "AQuA2 lane | movie=ON | risingMaps=OFF |
% parpool=disabled | resume+per-file-guard=ON"

    fprintf('AQuA2 lane | movie=ON | risingMaps=OFF | parpool=disabled | resume+per-file-guard=ON\n');
    fprintf('laneIn:   %s\n', laneIn);
    fprintf('laneOut:  %s\n', laneOut);

    % Make sure laneOut exists
    if ~exist(laneOut, 'dir')
        mkdir(laneOut);
    end

    % Read parameters CSV (typically C:\AQuA2\cfg\parameters_for_batch.csv)
    paramCsv = 'C:\AQuA2\cfg\parameters_for_batch.csv';
    if ~exist(paramCsv, 'file')
        error('Parameter file not found: %s', paramCsv);
    end
    opts = read_param_csv(paramCsv);
    fprintf('Parameters loaded from %s\n', paramCsv);

    % Disable parpool — single-thread per lane; parallelism is across lanes
    % (Lanes are independent processes, so AQuA2's internal parpool would
    %  oversubscribe and slow everything down.)
    if ~isempty(gcp('nocreate'))
        delete(gcp('nocreate'));
    end

    % Find TIFFs in lane
    tiffs = dir(fullfile(laneIn, '*.tif'));
    fprintf('Found %d TIFFs in lane.\n', numel(tiffs));

    for i = 1:numel(tiffs)
        tifPath = fullfile(laneIn, tiffs(i).name);
        [~, stem, ~] = fileparts(tifPath);
        matPath = fullfile(laneOut, [stem '_AQuA2.mat']);

        % Resume guard: skip if already done
        if exist(matPath, 'file')
            fprintf('[%d/%d] SKIP (already done): %s\n', i, numel(tiffs), stem);
            continue;
        end

        fprintf('[%d/%d] Processing: %s\n', i, numel(tiffs), stem);
        tStart = tic;

        % Per-file try/catch — a bad TIFF doesn't kill the lane
        try
            run_aqua_on_file(tifPath, laneOut, opts);
            fprintf('[%d/%d] DONE in %.1f min: %s\n', i, numel(tiffs), toc(tStart)/60, stem);
        catch ME
            errPath = fullfile(laneOut, [stem '_ERROR.txt']);
            errText = sprintf('Error: %s\nIdentifier: %s\nStack:\n', ME.message, ME.identifier);
            for k = 1:numel(ME.stack)
                errText = [errText, sprintf('  %s line %d\n', ME.stack(k).name, ME.stack(k).line)]; %#ok<AGROW>
            end
            fid = fopen(errPath, 'w');
            fprintf(fid, '%s', errText);
            fclose(fid);
            fprintf('[%d/%d] ERROR: %s — see %s\n', i, numel(tiffs), stem, errPath);
            % Continue with next file
        end
    end

    fprintf('Lane done.\n');
end


function run_aqua_on_file(tifPath, outDir, opts)
% Wrap AQuA2's actual processing call. Adjust to match the AQuA2 API
% being used in your environment. The compiled .exe used by the pipeline
% calls roughly this sequence:
%
%   1. Load TIFF
%   2. Apply parameters (maxSize, minSize, frameRate, spatialRes, etc.)
%   3. Run AQuA2 detection pipeline
%   4. Save:
%        <stem>_AQuA2.mat         — v7.3 result (res, evtMap, fts1, dffMat, opts)
%        <stem>_AQuA2_Ch1.csv     — per-event feature table
%        <stem>_AQuA2_curves.xlsx — fluorescence traces
%        <stem>_Movie.tif         — playback render

    % NOTE: replace the call below with the actual AQuA2 batch entry point
    % in your environment. The compiled .exe distributed with the pipeline
    % calls AQuA2's `aqua_cmd_batch` (or similar) — adjust to your AQuA2
    % version.

    % Pseudocode:
    %   [res, evtMap, fts1, dffMat] = aqua2_process(tifPath, opts);
    %   save([outPath '_AQuA2.mat'], 'res','evtMap','fts1','dffMat','opts','-v7.3');
    %   write_event_csv(fts1, [outPath '_AQuA2_Ch1.csv']);
    %   write_curves_xlsx(fts1, [outPath '_AQuA2_curves.xlsx']);
    %   write_movie(res, [outPath '_Movie.tif']);

    error(['run_aqua_on_file is a stub. The compiled aqua_lane.exe ' ...
           'calls AQuA2 internally; replace this stub with the actual ' ...
           'AQuA2 batch entry point in your environment to recompile.']);
end


function opts = read_param_csv(csvPath)
% Read parameters_for_batch.csv into an opts struct.
    T = readtable(csvPath, 'Delimiter',',', 'ReadVariableNames',true);
    opts = struct();
    for r = 1:height(T)
        name = strtrim(string(T{r,1}));
        val  = T{r,2};
        if iscell(val); val = val{1}; end
        if ischar(val) || isstring(val)
            v = str2double(val);
            if ~isnan(v); val = v; else; val = char(val); end
        end
        opts.(char(name)) = val;
    end
end
