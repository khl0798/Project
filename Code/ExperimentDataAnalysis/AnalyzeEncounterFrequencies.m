classdef AnalyzeEncounterFrequencies<handle
    % experimental setting:
    % investigation of TAD E and D in Nora et al 2012.
    % the DNA segment consists of 920432 bp, which are cut using restiction
    % enzymes into restiction fragments, using HINDIII restriction enzyme.
    % there are forward and backward restriction segments. 124 forward
    % (FOR) and 126 reverse (REV) segments of variable size. HindIII
    % recognized the site AAGCTT and cleaves it between the AA, leaving a
    % sticky end
    
    properties
        allData
        beadData
        segmentData
        encounterMatrix
        peaks
        results
        params
        beadSizeInbp = 3000;
        fitModel     = fittype(@(slope,x)(1./(sum(x.^(-slope)))).*x.^(-slope))
        %         fitModel     = fittype(@(slope,bias,x)(bias.*x.^(-slope)))
        creationDate = date;% class creation date
    end
    
    events
    end
    
    methods
        function obj = AnalyzeEncounterFrequencies()
            % Class constructor
        end
        
        function LoadDefaultParams(obj)
            % loads default parameters
            % default location of xls file
            obj.params.xlsFilePath = fullfile(pwd,'..','Data','Luca','MC_TAD_DE_E14d0_rep2+3_true.xlsx');
            obj.params.fillGapsBy   = 'sameValuesAsBoundary'; % when the dat is  missing (i.e, the segment takes the position of few beads,
            obj.params.beadRangeToAnalyze = [1 307]; % if empty, analyze all,
        end
        
        function SetInputParams(obj,params)
            % load input params. the param input must be a structure with
            % field names identical to the properties in obj.params
            fNames = fieldnames(params);
                for fIdx = 1:numel(fNames)
                    obj.params.(fNames{fIdx}) = params.(fNames{fIdx});
                end    
        end
        
        function Initialize(obj,params)
                        
            obj.LoadDefaultParams
            if exist('params','var')
                obj.SetInputParams(params)
            end                        
            
            obj.ReadData;% load data from xls
            obj.CreateEncounterFrequencyMatrices;
            obj.ProcessEncounters;
            obj.FitData;
            obj.FitMeanModel;
            obj.PeakCalling
            %            obj.DisplayEncounterMatrices;
        end
        
        function ReadData(obj)
            % a sequence of calls to list segments lengths and beads and
            % the transformations (interms of indices) between segments and
            % beads
            obj.ProcessAllData;
            
            obj.ProcessDataByBead;
            
            obj.ProcessDataBySegment;
            
        end
        
        function ProcessAllData(obj)
            % Read data from xls
            [values,~, obj.allData.all]= xlsread(obj.params.xlsFilePath);
            titles = {'beadStart1','beadEnd1','beadStart2','beadEnd2',...
                'rep1Count','rep2Count','averageCount','stdCount'};
            
            % Read data only in the valid range of beads
            if ~isempty(obj.params.beadRangeToAnalyze)
                range = obj.params.beadRangeToAnalyze;
                % take only beads in the range and such that have interactions with beads
                % in the range
                values = values(values(:,2)<=range(2) & values(:,1)>=range(1) & values(:,4)<=range(2) & values(:,3)>=range(1),:);
            end
            
            % store the data for each replicate of experiment and the
            % average
            for tIdx = 1:numel(titles);
                obj.allData.(titles{tIdx})= values(:,tIdx);
            end
        end
        
        function ProcessDataByBead(obj)
            % list unique segments and segment encounter
            allBeads1                     = unique([obj.allData.beadStart1,obj.allData.beadEnd1] ,'rows','stable');% unique segment 1
            allBeads2                     = unique([obj.allData.beadStart2,obj.allData.beadEnd2],'rows','stable'); % unique segment 2
            allBeads                      = unique([allBeads1;allBeads2],'rows');% uniqe segment encounter pairs
            obj.beadData.allBeads         = allBeads;
            obj.beadData.numBeads         = min([obj.params.beadRangeToAnalyze(2),307])- obj.params.beadRangeToAnalyze(1)+1;
            % the first index is the number of bead in which the restriction segment
            % starts. The second index (column) is the bead in which the
            % segment ends
            
        end
        
        function ProcessDataBySegment(obj)
            %          Find all unique bead lengths
            obj.segmentData.segmentLengthsInBeads = obj.beadData.allBeads(:,2)-obj.beadData.allBeads(:,1);
            % Create the encounter frequencies for each segment
            counter  = 1;
            for bIdx = 1:numel(obj.beadData.allBeads(:,1))
                
                obj.segmentData.segment(counter).segmentRangeInBeads       = [obj.beadData.allBeads(bIdx,1), obj.beadData.allBeads(bIdx,2)];
                obj.segmentData.segment(counter).existInDB                 = true;
                obj.segmentData.segment(counter).segmentLengthInBeads      = obj.beadData.allBeads(bIdx,2)- obj.beadData.allBeads(bIdx,1);
                obj.segmentData.segment(counter).segmentPositionInTheChain = counter;
                
                % if there is a gap between the present segment and the next
                % one, fill it with demi segment
                if bIdx~=numel(obj.beadData.allBeads(:,1)) && (obj.beadData.allBeads(bIdx+1,1)-obj.beadData.allBeads(bIdx,2))~=0
                    counter = counter+1;
                    obj.segmentData.segment(counter).segmentRangeInBeads       = [obj.beadData.allBeads(bIdx,2), obj.beadData.allBeads(bIdx+1,1)];
                    obj.segmentData.segment(counter).existInDB                 = false;
                    obj.segmentData.segment(counter).segmentLengthInBeads      = obj.beadData.allBeads(bIdx+1,1)- obj.beadData.allBeads(bIdx,2);
                    obj.segmentData.segment(counter).segmentPositionInTheChain = counter;
                end
                
                counter = counter+1;
            end
            
            obj.segmentData.histogram.freq   = hist([obj.segmentData.segment(:).segmentLengthInBeads],obj.beadData.numBeads);% length distribution
            obj.segmentData.histogram.bins   = obj.beadSizeInbp:obj.beadSizeInbp:obj.beadSizeInbp*obj.beadData.numBeads;
            obj.segmentData.histogram.xLabel = 'Estimated Segment Length';
            obj.segmentData.histogram.yLabel = 'Frequency';
            %            obj.PlotSegments
        end
        
        function ProcessEncounters(obj)
            % Process encounters by bead
            expNames = {'rep1','rep2','average'};
            for eIdx = 1:3
                allFreq     = obj.encounterMatrix.(expNames{eIdx});
                eMatrix     = cell(obj.beadData.numBeads,1);
                
                for bIdx = 1:size(allFreq,1)% for each bead
                    before = allFreq(bIdx,bIdx-1:-1:1);% flipped
                    after  = allFreq(bIdx,bIdx+1:1:end);
                    freq   = zeros(2,obj.beadData.numBeads-1);
                    freq(1,1:numel(before)) = before;
                    freq(2,1:numel(after))  = after;
                    normFac = ones(1,size(freq,2));
                    normFac(1:min([numel(before),numel(after)])) = 2;
                    freq = sum(freq)./normFac; % this becomes the average of before and after;
                    
                    % record the 'before' and 'after' encounter frequency.
                    % where 'before' and 'after' mean in terms of index
                    obj.beadData.encounterData.twoSides.(expNames{eIdx}){bIdx,1} = before;
                    obj.beadData.encounterData.twoSides.(expNames{eIdx}){bIdx,2} = after;
                    eMatrix{bIdx} = freq;
                end
                obj.beadData.encounterData.oneSide.(expNames{eIdx}) = eMatrix;
            end
        end
        
        function CreateEncounterFrequencyMatrices(obj)
            % For the two replicates and the average, create encounter
            % frequency matrices. These matrices represent the even
            % partition of the genome. Each bead's length is 3000bp.
            mumBeads                    = obj.beadData.numBeads;
            obj.encounterMatrix.rep1    = zeros(mumBeads);
            obj.encounterMatrix.rep2    = zeros(mumBeads);
            obj.encounterMatrix.average = zeros(mumBeads);
            
            for bIdx = 1:numel(obj.allData.beadStart1);
                bs1 = obj.allData.beadStart1(bIdx)-obj.params.beadRangeToAnalyze(1)+1;
                be1 = obj.allData.beadEnd1(bIdx)-obj.params.beadRangeToAnalyze(1)+1;
                bs2 = obj.allData.beadStart2(bIdx)-obj.params.beadRangeToAnalyze(1)+1;
                be2 = obj.allData.beadEnd2(bIdx)-obj.params.beadRangeToAnalyze(1)+1;
                for bsIdx = bs1:be1
                    for beIdx = bs2:be2
                        obj.encounterMatrix.rep1(bsIdx,beIdx)    = obj.encounterMatrix.rep1(bsIdx,beIdx)+obj.allData.rep1Count(bIdx);
                        obj.encounterMatrix.rep1(beIdx,bsIdx)    = obj.encounterMatrix.rep1(beIdx,bsIdx)+obj.allData.rep1Count(bIdx);
                        
                        obj.encounterMatrix.rep2(bsIdx,beIdx)    = obj.encounterMatrix.rep2(bsIdx,beIdx)+obj.allData.rep2Count(bIdx);
                        obj.encounterMatrix.rep2(beIdx,bsIdx)    = obj.encounterMatrix.rep2(beIdx,bsIdx)+obj.allData.rep2Count(bIdx);
                        
                        obj.encounterMatrix.average(bsIdx,beIdx) = obj.encounterMatrix.average(bsIdx,beIdx)+obj.allData.averageCount(bIdx);
                        obj.encounterMatrix.average(beIdx,bsIdx) = obj.encounterMatrix.average(beIdx,bsIdx)+obj.allData.averageCount(bIdx);
                    end
                end
            end
        end
        
        function FitData(obj)
            % Fit a function of the form y = a*x^-b to each monomer
            % encounter frequency data
            fNames = {'rep1','rep2','average'};
            model                = obj.fitModel;
            fOptions             = fitoptions(model);
            fOptions.TolX        = 1e-8;
            fOptions.TolFun      = 1e-8;
            fOptions.MaxFunEvals = 1e3;
            fOptions.MaxIter     = 1e3;
            fOptions.StartPoint  = 1.5; % [slope]
            fOptions.Lower       = 0.2; % [slope]
            fOptions.Robust      = 'Bisquare';
            %             fOptions.Display     = 'iter';
            for fIdx = 1:numel(fNames);
                prevMissing = false;% indicateor of whether the previous bead is missing.
                missingIdx  = [];% missing beads indices
                for bIdx = 1:size(obj.beadData.encounterData.oneSide.(fNames{fIdx}),1)
                    
                    freq = obj.beadData.encounterData.oneSide.(fNames{fIdx})(bIdx,1);% raw data
                    if ~all(freq{:}==0)% if it is present in the database
                        freq = {freq{:}./sum(freq{:})};% normalize to create probability
                    end
                    
                    y = freq{:}';
                    % Ignore missing data
                    includedPlaces = y~=0;
                    y = y(includedPlaces);
                    x = find(includedPlaces);
                    
                    if ~all(y==0)
                        [fitObject, gof] = fit(x,y,model,fOptions);
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx})                 = obj.NewFitResultsStruct;
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).bias            = (1/sum((1:obj.beadData.numBeads-1).^(-fitObject.slope)));
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).exp             = fitObject.slope;
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).gof             = gof;
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).beadDist        = x;
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).encounterNumber = freq{:}(includedPlaces)';
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).encounterProb   = y;%freq{:}';
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).functionValues  = model(fitObject.slope,x);
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).model           = model;
                        obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).existInDb       = true;
                        % save data in a struct for easy plotting
                        obj.results.fit.(fNames{fIdx}).exp(bIdx)                          = fitObject.slope;
                        obj.results.fit.(fNames{fIdx}).bias(bIdx)                         = obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).bias ;
                        
                        if prevMissing
                            if strcmpi(obj.params.fillGapsBy,'sameValuesAsBoundary')% options [sameValueAsBoundary/Interp]
                                % fill-in the gaps with fit values obtained at
                                % the boundary of the gap
                                bStart  = (obj.beadData.bead(missingIdx(1)-1).fitResults.(fNames{fIdx}).bias);
                                bEnd    = (obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).bias);
                                bValues = linspace(bStart,bEnd,numel(missingIdx));% linear interpolation of the bias values
                                eStart  = obj.beadData.bead(missingIdx(1)-1).fitResults.(fNames{fIdx}).exp;
                                eEnd    = obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).exp;
                                eValues = linspace(eStart,eEnd,numel(missingIdx));% linear interpolation of the exp values
                                for mIdx = 1:numel(missingIdx)
                                    obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx})              = obj.NewFitResultsStruct;
                                    obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).bias     = bValues(mIdx);
                                    obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).exp      = eValues(mIdx);
                                    obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).gof      = 'missing bead- data interpolated from nearest neighbor';
                                    obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).beadDist = obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).beadDist;
                                    obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).encounterNumber = [];
                                    obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).encounterProb   = [];
                                    obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).functionValues  = [];
                                    obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).existInDb       = false;
                                    obj.results.fit.(fNames{fIdx}).exp(missingIdx(mIdx))  = obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).exp;
                                    obj.results.fit.(fNames{fIdx}).bias(missingIdx(mIdx)) = obj.beadData.bead(missingIdx(mIdx)).fitResults.(fNames{fIdx}).bias;
                                end
                                missingIdx  = [];% reset the missing idx
                                prevMissing = false;% reset the missing flag
                            end
                        else
                            obj.results.fit.(fNames{fIdx}).exp(bIdx)  = fitObject.slope;
                            obj.results.fit.(fNames{fIdx}).bias(bIdx) = fitObject.slope-1;
                        end
                    else
                        prevMissing = true;
                        missingIdx(end+1) = bIdx;% record the indices of the missing beads in the block
                    end
                end
            end
        end
        
        function FitMeanModel(obj)
            % Calculate the mean of the mean data
            %             n = zeros(1,obj.beadData.numBeads-1);
            n     = zeros(1,obj.beadData.numBeads-1);
            dists = 1:obj.beadData.numBeads-1;
            
            for bIdx = 1:obj.beadData.numBeads
                normEncounter = obj.beadData.encounterData.oneSide.average{bIdx};
                if all(normEncounter==0)
                    
                else
                    normEncounter = normEncounter/sum(obj.beadData.encounterData.oneSide.average{bIdx});
                end
                n = n+normEncounter;
            end
            n     = n./obj.beadData.numBeads;% divide to get the mean
            obj.results.fit.allData.meanEncounterProb = n;
            model                = obj.fitModel;
            fOptions             = fitoptions(model);
            fOptions.TolX        = 1e-10;
            fOptions.TolFun      = 1e-10;
            fOptions.MaxFunEvals = 1e6;
            fOptions.MaxIter     = 1e6;
            fOptions.StartPoint  = 1.5;% [slope]
            fOptions.Lower       = 0.2;% [slope]
            fOptions.Weights      = n'~=0;
            
            [fitObject, gof]              = fit(dists',n',model,fOptions);
            obj.results.fit.allData.bias  = 1/(sum(dists.^(-fitObject.slope)));
            obj.results.fit.allData.exp   = fitObject.slope;
            obj.results.fit.allData.gof   = gof;
            obj.results.fit.allData.model = model;
            
        end
                
        function PeakCalling(obj)
            % Find peaks in the two sided encounter data
            % for TAD D            
            %             if obj.params.beadRangeToAnalyze(1)==1 && obj.params.beadRangeToAnalyze(2)== 108
            fNames = {'Rep1','Rep2','Average'};
            for fIdx=1:numel(fNames)
                numBeads           = obj.params.beadRangeToAnalyze(2)-obj.params.beadRangeToAnalyze(1)+1;
                oneSided           = zeros(numBeads-1);
                encounterLeft      = zeros(numBeads-1);
                encounterRight     = zeros(numBeads-1);
                pMatLeft           = zeros(numBeads);
                pMatRight          = zeros(numBeads);
                peakList           = [];
                
                expectedEncountersStd = zeros(1,numBeads-1);
                
                % The expected signal
                for bIdx = 1:numBeads-1
                    oneSided(bIdx,:) = obj.beadData.encounterData.oneSide.(lower(fNames{fIdx})){bIdx};%(obj.params.beadRangeToAnalyze(1):obj.params.beadRangeToAnalyze(2)-1);
                end
                
                tr                 = tril(ones(numBeads-1));
                tr                 = tr+fliplr(tr');
                tr                 = double(tr~=0);
                numValidObs        = sum(tr);% the number of available observations for each genomic distance
                expectedEncounters = sum(oneSided)./numValidObs;% divide to get the expected mean signal
                
                for bIdx = 1:numBeads-1
                    expectedEncountersStd(bIdx) = std(oneSided(tr(:,bIdx)~=0,bIdx));
                end
                
                % build the encounter matrix on the left and right
                
                threshCurve = expectedEncounters+4*expectedEncountersStd; % find outliers
                for bIdx = 1:numBeads-1% for each bead
                    leftObs  = obj.beadData.encounterData.twoSides.rep1{bIdx,1};
                    rightObs = obj.beadData.encounterData.twoSides.rep1{bIdx,2};
                    encounterLeft(bIdx,1:numel(leftObs))   = leftObs;
                    encounterRight(bIdx,1:numel(rightObs)) = (rightObs);
                    tLeft  = leftObs>threshCurve(1:numel(leftObs));
                    tRight = rightObs>threshCurve(1:numel(rightObs));
                    if~isempty(tLeft)
                        pMatLeft(bIdx,bIdx-1:-1:bIdx-numel(tLeft)) = tLeft;
                    end
                    if ~isempty(tRight)
                        pMatRight(bIdx,bIdx+1:bIdx+numel(tRight)) = tRight;
                    end
                end
                
                % Remove nearest neighbor interactions
                pMatLeft(diag(ones(numBeads-1,1),-1)~=0)= 0;
                pMatRight(diag(ones(numBeads-1,1),1)~=0)= 0;
                
                % combine left-right encounters
                combPeaks = (pMatLeft+pMatRight')~=0;
                [peakList(:,1), peakList(:,2)] = find(combPeaks);
                
                peakList = sortrows(peakList,1);
                obj.peaks.(lower(fNames{fIdx})) =  peakList+obj.params.beadRangeToAnalyze(1)-1;
            end
        end
        
        function DisplayAllDataFit(obj,dispScale)
            % display mean encounter data fit
            if~exist('dispScale','var');
                dispScale = 'linear';
            end
            f = figure('FileName','meanDataFit');
            a = axes('Parent',f,...
                'NextPlot','Add',...
                'XScale',dispScale,...
                'YScale',dispScale,...
                'NextPlot','Add',...
                'FontSize',40,...
                'XLim',[1 obj.beadData.numBeads]);
            
            xlabel(sprintf('%s','Distance [beads]'),'FontSize',40);
            ylabel(sprintf('%s','Encounter Prob.'),'FontSize',40);
            title('Mean Data Fit','fontSize', 40)
            
            for bIdx = 1:numel(obj.beadData.bead);
                if~isempty(obj.beadData.bead(bIdx).fitResults.average.encounterProb)
                    
                    lineC = rand(1,3);
                    line('XData',obj.beadData.bead(bIdx).fitResults.average.beadDist,...
                        'YData',obj.beadData.bead(bIdx).fitResults.average.encounterProb,...
                        'Color',lineC,...
                        'Marker','o',...
                        'MarkerSize',2,...
                        'MarkerEdgeColor',lineC,...
                        'MarkerFaceColor','k',...
                        'LineStyle','-',...
                        'LineWidth',3,...
                        'DisplayName',sprintf('%s%s','Bead',num2str(bIdx)),...
                        'handleVisibility','off',...
                        'Parent',a)
                else
                    %                         sprintf('%s%s%a', sprintf('%s%s',' fit for bead ',num2str((bIdx))),' is empty')
                end
            end
            
            % plot the fitted line
            A = obj.results.fit.allData.bias;
            B = obj.results.fit.allData.exp;
            line('XData',1:obj.beadData.numBeads-1,...
                'YData',(A*(1:obj.beadData.numBeads-1).^(-B)),...
                'LineStyle','-',...
                'LineWidth',7,...
                'Color','r',...
                'DisplayName',['mean data fit. \beta =' num2str(B)] );
            legend(get(a,'Children'));
            
        end
        
        function DisplayEncounterMatrices(obj, windowSize)
            % Display the encounter matrices. the pixels of the matrices
            % indicate the number of times bead i met bead j.
            % the parameter windowsize, determine the window size of the
            % median filter. The median filter is utilized to follow the
            % protocol used by Nora et al 2012.
            % windowSize must be a positive integer.
            if ~exist('windowSize','var')
                windowSize = 1;
            end
            cmap = hot(256);% define color map
            
            % display rep1
            figure('Name','EncounterMatrix Rep1','FileName','encounterMatrixRep1');
            emRep1  = medfilt2(obj.encounterMatrix.rep1,[windowSize,windowSize]);
            maxRep1 = max(emRep1(:));
            emRep1 = emRep1./maxRep1;% normalize
            
            % construct a color scheme from white to black through red such
            % that black is
            imagesc(emRep1);
            set(gca,'FontSize',40)
            title(gca,'replicate 1','FontSize',40);
            colormap((cmap))
            axis ij
            
            % display rep2
            figure('Name','EncounterMatrix Rep2','FileName','encounterMatrixRep2');
            imagesc(medfilt2(obj.encounterMatrix.rep2,[windowSize,windowSize]));
            title('replicate 2','FontSize',40);
            set(gca,'FontSize',40);
            colormap((cmap))
            axis ij
            
            % display average
            figure('Name','EncounterMatrix average','FileName','encounterMatrixAverage');
            emAverage  = medfilt2(obj.encounterMatrix.rep2,[windowSize,windowSize]);
            maxAverage = max(emAverage(:));
            emAverage  = emAverage./maxAverage;
            imagesc(emAverage);
            set(gca,'FontSize',40);
            title(gca,'Replicates Average');
            colormap(flipud(cmap))
            axis ij
%             colormapeditor
        end
        
        function DisplayEncounterProbabilityByBead(obj,beads,dispScale,sides)
            if ~exist('beads','var')
                beads = 1:numel(obj.beadData.bead);
            end
            if ~exist('dispScale','var')
                dispScale = 'linear';% axes display scale [linear/log]
            end
            
            if ~exist('sides','var')
                sides = 'oneSide';
            end
                        
            fNames = {'Rep1','Rep2','Average'};
            for fIdx = 1:numel(fNames)
                % create main figure
                f = figure('FileName',['encounterProbabilityByDistance',fNames{fIdx}],...
                    'Name',['encounterProbabilityByDistance',fNames{fIdx}]);
                if strcmpi(sides,'oneSide')
                    xLim = [1 obj.beadData.numBeads];
                elseif strcmpi(sides,'twoSides')
                    xLim = [-obj.beadData.numBeads obj.beadData.numBeads];
                end
                % create main axes
                a = axes('Parent',f,...
                    'NextPlot','Add',...
                    'XScale',dispScale,...
                    'YScale',dispScale,...
                    'FontSize',40,...
                    'XLim',xLim);
                
                xlabel(sprintf('%s','Distance [beads]'),'FontSize',40);
                ylabel(sprintf('%s','Prob. Encounter'),'FontSize',40);
                
                title(fNames{fIdx},'fontSize',40)
                for bIdx = beads
                    if~isempty(obj.beadData.bead(bIdx).fitResults.(lower(fNames{fIdx})).encounterProb)
                        fResults = obj.beadData.bead(bIdx).fitResults.(lower(fNames{fIdx}));
                        % indicate whether the bead is missing in the
                        % legend
                        if fResults.existInDb
                            dispName = sprintf('%s%s','Bead',num2str(bIdx));
                        else
                            dispName = sprintf('%s%s%s','Bead',num2str(bIdx),' (missing)');
                        end
                        if strcmpi(sides,'oneSide')
                            % plot the encoutner data and fit
                            line('XData',fResults.beadDist,...
                                'YData',fResults.encounterProb,...
                                'Color',rand(1,3),...
                                'Marker','.',...
                                'MarkerSize',7,...
                                'LineStyle','-',...
                                'LineWidth',3,...
                                'DisplayName',dispName,...
                                'Parent',a);
                        elseif strcmpi(sides,'twoSides')
                            eData = [fliplr(obj.beadData.encounterData.twoSides.(lower(fNames{fIdx})){bIdx,1}),...
                                obj.beadData.encounterData.twoSides.(lower(fNames{fIdx})){bIdx,2}];
%                             eData = eData./sum(eData(:)); % convert to probability 
                            line('XData',(1:numel(eData))-bIdx,...
                                'YData',eData,...
                                'Color',rand(1,3),...
                                'Marker','.',...
                                'MarkerSize',7,...
                                'LineStyle','-',...
                                'LineWidth',3,...
                                'DisplayName',dispName,...
                                'Parent',a);
                        end                                                
                    else
                        % do nothing
                    end
                end
            end
        end
        
        function DisplayFittedParameters(obj)
            % Display the fitted parameters of the encounter probability, using the model defined in obj.modelfit,
            % for the two replicas and their average
            fNames = {'Rep1','Rep2','Average'};
            for fIdx = 1:numel(fNames)
                % plot fitted beta values
                expFigName = sprintf('%s%s','\beta for ', fNames{fIdx});
                
                % create main figure
                fe = figure('Name',expFigName,...
                    'FileName',['FittedExpValues',fNames{fIdx}]);
                % create main axes
                ae = axes('Parent',fe,...
                    'FontSize',40,...
                    'XLim',[1 obj.beadData.numBeads],...
                    'NextPlot','Add');
                
                title(ae,expFigName,'FontSize',40);
                xlabel(ae,'Bead number','FontSize',40);
                ylabel(ae,'Fitted \beta','FontSize',40);
                
                % plot fitted bias values
                biasFigName = sprintf('%s%s','Bias for ', fNames{fIdx});
                
                fb = figure('Name',biasFigName,...
                    'FileName',['FittedExpValues',fNames{fIdx}]);
                ab = axes('Parent',fb,...
                    'FontSize',40,...
                    'XLim',[1 obj.beadData.numBeads],...
                    'NextPlot','Add');
                
                title(ab,biasFigName,'FontSize',40);
                xlabel(ab,'Bead number','FontSize',40);
                ylabel(ab,'Fitted bias','FontSize',40);
                
                
                for bIdx = 1:numel(obj.beadData.bead);
                    % indicate whether the bead is missing in the legend
                    if obj.beadData.bead(bIdx).fitResults.(lower(fNames{fIdx})).existInDb
                        dispName = ['bead ', num2str(bIdx)];
                    else
                        dispName = ['bead ', num2str(bIdx),' (missing)'];
                    end
                    % plot the values of the fitted exponent
                    line('Parent',ae,...
                        'XData',bIdx,...
                        'YData',obj.beadData.bead(bIdx).fitResults.(lower(fNames{fIdx})).exp,...
                        'LineStyle','none',...
                        'Marker','o',...
                        'MarkerFaceColor','b',...
                        'DisplayName',dispName)
                    
                    % plot the values of the fitted bias
                    line('Parent',ab,...
                        'XData',bIdx,...
                        'YData',obj.beadData.bead(bIdx).fitResults.(lower(fNames{fIdx})).bias,...
                        'Marker','o',...
                        'MarkerFaceColor','b',...
                        'LineStyle','none',...
                        'DisplayName',dispName);
                end
                
            end
        end
        
        function DisplayFitByBead(obj,beadNumbers,dispScale)
            warning off
            fNames = {'rep1','rep2','average'};
            if ~exist('beadNumbers','var')||strcmpi(beadNumbers,'all')
                beadNumbers = 1:obj.beadData.numBeads;
            end
            
            if ~exist('dispScale','var')
                dispScale = 'linear';
            end
            for fIdx = 1:numel(fNames)
                f = figure('Name',['FitByBead',fNames{fIdx}]);
                a = axes('Parent',f,...
                    'NextPlot','Add',...
                    'XScale',dispScale,...
                    'YScale',dispScale,...
                    'NextPlot','Add',...
                    'FontSize',40);
                
                xlabel(sprintf('%s','Distance [beads]'),'FontSize',40);
                ylabel(sprintf('%s','Num. encounters'),'FontSize',40);
                title(fNames{fIdx},'FontSize',40)
                % line color
                lineC = [linspace(0,1,numel(beadNumbers))',0.5*ones(numel(beadNumbers),1),0.5*ones(numel(beadNumbers),1)];
                
                for bIdx = 1:numel(beadNumbers)
                    if~isempty(obj.beadData.bead(beadNumbers(bIdx)).fitResults)
                        %                         freq = obj.beadData.bead(beadNumbers(bIdx)).fitResults.(fNames{fIdx}).encounterNumber;
                        %                         freq(freq==0)=NaN;
                        % indicate in the legend if the bead is missing
                        if obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).existInDb
                            dispName = sprintf('%s%s','Bead',num2str(beadNumbers(bIdx)));
                        else
                            dispName = sprintf('%s%s','Bead',num2str(beadNumbers(bIdx)),' (missing)');
                        end
                        line('XData',obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).beadDist,...
                            'YData',obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).encounterProb,...
                            'Color',lineC(bIdx,:),...
                            'Marker','none',...
                            'MarkerSize',2,...
                            'MarkerEdgeColor','c',...
                            'MarkerFaceColor','k',...
                            'LineStyle','-',...
                            'LineWidth',2,...
                            'DisplayName',dispName,...
                            'Parent',a)
                        
                        % plot the fitted line
                        A = obj.beadData.bead(beadNumbers(bIdx)).fitResults.(fNames{fIdx}).bias;
                        B = obj.beadData.bead(beadNumbers(bIdx)).fitResults.(fNames{fIdx}).exp;
                        line('XData',obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).beadDist,...
                            'YData',(A*(obj.beadData.bead(bIdx).fitResults.(fNames{fIdx}).beadDist).^(-B)),...
                            'LineStyle','-',...
                            'LineWidth',4,...
                            'Color','r',...
                            'DisplayName',['Bead ',num2str(bIdx),' \beta: ',num2str(B), ' bias: ',num2str(A)]);
                        
                    else
                        sprintf('%s%s%a', sprintf('%s%s','Bead',num2str(beadNumbers(bIdx))),'is empty');
                    end
                end
            end
        end
        
        function PlotSegments(obj)
            % plot a cylinder representing the polymer, with red
            % representing missing segments in the data
            maxBead     = obj.beadData.numBeads;
            allSegments = obj.beadData.allBeads;
            
            segmentLength = 1;
            pLength       = maxBead;
            
            % plot the missing pieces
            f = figure('MenuBar','none');
            a = axes('Parent',f,...
                'NextPlot','Add');
            % create a cylinder lines
            t  = linspace(0,2*pi,50);
            r  = 10;
            x  = repmat(r*cos(t),pLength,1);
            y  = repmat(r*sin(t),pLength,1);
            z  = repmat((1:pLength)',1,numel(t));
            c  = 255*ones(size(x));
            m  = mesh(x,y,z,'Parent',a,...
                'CData',c,...
                'FaceColor','b',...
                'CDataMapping','scaled',...
                'FaceLighting','gouraud');
            
            for bIdx = 1:numel(allSegments(:,1))
                % plot places where we know segments exist for the
                % experiments
                c   = get(m,'CData');
                c((allSegments(bIdx,1)-1)*segmentLength+1:(allSegments(bIdx,2))*segmentLength,:)=0;
                set(m,'CData',c);
            end
            
            daspect([1 1 1]);
            cameratoolbar
        end
        
        function obj = ReloadObj(obj,structIn)
            % Reload a constructed obj with a structure
            prop= properties(structIn);
            for fIdx = 1:numel(prop)
                obj.(prop{fIdx}) = structIn.(prop{fIdx});
            end
        end
        
        function objOut = SaveObj(obj)
            % Save the object to a structure for saving as mat file
            prop= properties(obj);
            for fIdx = 1:numel(prop)
                objOut.(prop{fIdx}) = obj.(prop{fIdx});
            end
            uisave('objOut')
        end
        
        function FitCurveToExpData(obj,smoothingFac)
            % fit a curve to the exponents of the fitted encounter
            % frequency data. use a smoothing spline with a smoothingFac>0
            if ~exist('smoothingFac','var')
                smoothingFac = 1;
            end
            fNames = {'Rep1','Rep2','Average'};
            % fit using a smoothing spline
            for fIdx = 1:numel(fNames)
                [obj.results.fit.(lower(fNames{fIdx})).expSpline,~] = spaps(1:numel(obj.results.fit.(lower(fNames{fIdx})).exp),...
                    obj.results.fit.(lower(fNames{fIdx})).exp',smoothingFac);
                
                f = figure('Name',['fittedExpValuesWithSpline',fNames{fIdx}],...
                    'FileName',['fittedExpValuesWithSpline',fNames{fIdx}]);
                a = axes('Parent',f,...
                    'NextPlot','Add',...
                    'FontSize',40,...
                    'XLim',[1 obj.beadData.numBeads],...
                    'YLim',[0 max(obj.results.fit.(lower(fNames{fIdx})).exp)+0.2]);
                
                line('XData',1:numel(obj.beadData.bead),...
                    'YData',obj.results.fit.(lower(fNames{fIdx})).exp,...
                    'Marker','o',...
                    'MarkerEdgeColor','k',...
                    'MarkerSize',8,...
                    'MarkerFaceColor','b',...
                    'lineStyle','none',...
                    'DisplayName','\beta',...
                    'Parent',a);
                
                title(sprintf('%s%s','Fitted \beta for ', fNames{fIdx}),'FontSize',40);
                xlabel('Bead number','FontSize',40);
                ylabel('Fitted \beta values','FontSize',40);
                
                % plot the smoothing spline
                fn = fnplt(obj.results.fit.(lower(fNames{fIdx})).expSpline);
                line('XData',fn(1,:),...
                    'YData',fn(2,:),...
                    'DisplayName','Spline',...
                    'Parent',a,...
                    'LineWidth',3,...
                    'Color','k');
                
                legend(get(a,'Children'))
            end
        end        
        
        function CheckEncounterDataSymmetry(obj)
            % Check the two-sided encounter data for each bead.
            % The encounter data of 'left' and 'right' are compared by
            % taking the difference of the minimal number of beads of both
            % sides.
            fNames = {'Rep1','Rep2','Average'};
            d = zeros(obj.beadData.numBeads,numel(fNames));
            meanDiff = zeros(1,numel(fNames));
            for fIdx = 1:numel(fNames)
                for bIdx = 1:numel(obj.beadData.encounterData.twoSides.(lower(fNames{fIdx}))(:,1))
                    % find the end with the least number of beads
                    [~,m] = min([numel(obj.beadData.encounterData.twoSides.(lower(fNames{fIdx})){bIdx,1}),...
                        numel(obj.beadData.encounterData.twoSides.(lower(fNames{fIdx})){bIdx,2})]);
                    numPoints = numel(obj.beadData.encounterData.twoSides.(lower(fNames{fIdx})){bIdx,m});
                    
                    if ~isempty(obj.beadData.encounterData.twoSides.(lower(fNames{fIdx})){bIdx,1})
                        
                        pLeft = obj.beadData.encounterData.twoSides.(lower(fNames{fIdx})){bIdx,1}(1:numPoints);
                        pLeft = pLeft./sum(pLeft);
                        
                        pRight = obj.beadData.encounterData.twoSides.(lower(fNames{fIdx})){bIdx,2}(1:numPoints);
                        pRight = pRight./sum(pRight);% get prob by normalizeing
                        
                        d(bIdx,fIdx) = mean(pLeft-pRight);
                    else
                        d(bIdx,fIdx) = NaN;
                    end
                end
                
                meanDiff(fIdx) = mean(d(~isnan(d(:,fIdx)),fIdx));
                
                f(fIdx) = figure;
                ax(fIdx) = axes('Parent',f(fIdx),'NextPlot','Add');
                
                % plot the mean prob difference of the two sides for each bead
                line('XData',1:obj.beadData.numBeads,...
                    'YData',d(:,fIdx),'Linewidth',6,...
                    'Parent',ax(fIdx),...
                    'DisplayName','two-sided encounter Prob diff.',...
                    'Color','b')
                % plot the mean prob difference of the two sides for all beads
                line('XData',[1,numel(d(:,fIdx))],...
                    'YData',meanDiff(fIdx)*ones(1,2),...
                    'Color','r',...
                    'LineWidth',6,...
                    'Parent',ax(fIdx),...
                    'DisplayName','mean prob diff')
                
                xlabel('Bead number','FontSize',40);
                ylabel('mean encounter prob. difference','FontSize',40);
                title(fNames{fIdx},'Fontsize',40)
                set(gca,'Fontsize',40)
                legend(get(ax(fIdx),'Children'));
            end
            
        end
    end
    
    methods (Static)
        
        function objOut = LoadObj(objIn)
            % Constuct the objec with a structure objIn
            if nargin<1
                objIn = uiload('*.mat');
            end
            objOut = AnalyzeEncounterFrequencies;
            objOut = ReloadObj(objOut,objIn);
        end
        
        function fitRStruct = NewFitResultsStruct()
            % create a new fitting structure to hold results
            fitRStruct = struct('bias',[],...
                'exp',[],...
                'gof',[],...
                'beadDist',[],...
                'encounterNumber',[],...
                'encounterProb', [],...
                'functionValues',[],...
                'existInDb',[],...
                'model',[]);
        end
        
        function valsOut = model(x,encounterData)%unused
            % this si the SSD of the fitted parameters
            % encounterData is a two column vector. the first column is the
            % encounter frequencies, the second is the index of included
            % beads.
            % encounterData(:,1) - log(encounter frequencies)
            % encounterData(:,2) - log(included bead indices)
            % x(1) - is the bias
            % x(2) - is the slope
            logBeadDist      = encounterData(:,2);
            logEncounterFreq = encounterData(:,1);
            valsOut = (sum((x(1)-x(2)*logBeadDist-logEncounterFreq).^2));
        end
        
        function [valInEq, valEq] = modelConstraint(x,includedBeads)
            % constrain of the fitted model
            % we wish the sum of elements to be one
            logBeadDist = includedBeads;
            valEq       = sum(exp(x(1)-x(2)*logBeadDist))-1;% *numel(includedBeads)-x(2)*sum((includedBeads))-1;
            valInEq     = valEq;
        end
        
        function sigOut=LoessSmooth(sigIn)
            % smooth the signal in sigIn with a loess filter 
            sigOut = smooth(sigIn',11,'loess');
        end
    end
    
    % private methods 
    methods (Access=private)
        
    end
end