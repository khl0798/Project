classdef CalculateBeadDistancesByRouseModel<handle
    
    properties (Access=public)
        encounterMat
        connectivityMat
        beadRange       % set bead range for TAD D
        smoothingMethod % see smooth function for options 
        smoothingSpan   % smoothing span for the encounter probability signal
        numDistances    % for how many distances to perform analysis for connectivity
        distToAnalyze   % can be a vector of integers, for what disance to show the analysis
        beadsToAnalyze  % for what beads to show the connectivity graphs
        zeroInterpolationMethod % how to fill in nan values of the encounter signal [ linear, nearest, spline, cubic,...]
        prob2distMethod % how to transform probability into distance [fitModel,rouse,composite]
        graph
        model
        chain           % the Rouse chain class
        fitOpt
        dataFolder
        dataFileName
    end
    
    properties (Access=private)
        smoother = Smoother; % signal smoother class
    end
    
    methods
        
        function obj = CalculateBeadDistancesByRouseModel
            % class constructor 
            obj.SetDefaultParams;
        end
        
        function SetDefaultParams(obj)
            obj.beadRange      = struct('bead1',1:307,...
                                        'bead2',1:306); % bead range to analyze in the encounterMat
            obj.smoothingSpan  = 10;                  % can be a vector of integer, in the present version only the last span is considered
            obj.smoothingMethod= 'Mulambda';          % see smooth function for options 
            obj.numDistances   = 1;                   % for how many distances to perform analysis for connectivity
            obj.distToAnalyze  = 1;                   % can be a vector of integers, for what disance to show the analysis
            obj.beadsToAnalyze = 1;                   % for what beads to show the connectivity graphs
            obj.zeroInterpolationMethod = 'linear';   % how to fill in gaps for zero values of the encoutner signal (see interp1 documentation for methods)
            obj.prob2distMethod         = 'rouse'; % how to transform probability into distance [fitModel,rouse,composite]
            obj.model          = fittype('(1/sum(x.^(-beta))).*x.^(-beta)'); % the model to be used to fit probabilities 
            obj.fitOpt         = fitoptions(obj.model);                      % fiting options 
            set(obj.fitOpt,'Lower',0,'Upper',1.5,'StartPoint',1,'Robust','off');
            obj.dataFolder     = fullfile(pwd,'ExperimentDataAnalysis');     % default data folder
            obj.dataFileName   = 'savedAnalysisTADDAndE';                    % name of dataset
        end
        
        function Initialize(obj,encounterMat)
            
            if exist('encounterMat','var')
                obj.ProcessEncounterMatrix(encounterMat);
            else
                obj.ProcessEncounterMatrix
            end
                                   
            % Preallocations
            above = cell(1,numel(obj.beadRange.bead1));% save indices of distances falling above the nearest neighor encounter probability
            dists = cell(size(obj.encounterMat,1),size(obj.encounterMat,2));
            histK = cell(size(obj.encounterMat,1),size(obj.encounterMat,2));
            
            % Construct a binary connection matrix for a specific distance
            eMat = false(numel(obj.beadRange.bead1),numel(obj.beadRange.bead1),obj.numDistances);
            di   = diag(ones(1,size(eMat,1)-1),1)+diag(ones(1,size(eMat,1)-1),-1);% include nearest neighbors by default
                                    
            for bIdx = 1:size(obj.encounterMat,1);% for each bead
                
                % Interpolate and smooth the encounter signal 
%                 observedProb = obj.ProcessBeadEncounterSignal(obj.encounterMat(bIdx,:));                
                  observedProb = obj.encounterMat(bIdx,:);
                  
                if ~all(isnan(observedProb))                                        
                    % Divide the probabilites into distances according to a division given by the
                    % expected model

                    [bDists,modelValues] = obj.TransformProbToDist(observedProb);
%                     [chainRingStruct]    = obj.AnalyzeEncounterAsRingsAndChains(observedProb);
                    % obtain the values of the composite structure
%                     vals = obj.GetCompositeFunctionVals(chainRingStruct);
                    
                    % display
                    if mod(bIdx,408)==0
                        obj.PlotBeadClusteringByDistance(observedProb,inds,modelValues);
                        title(num2str(bIdx))
                    end
                                                          
                    % Calculate the histogram
                    above{bIdx} = find(observedProb>modelValues(1));
                    below{bIdx} = [];
                    for kIdx = 1:numel(modelValues)-1
                        dists{bIdx,kIdx} = find(observedProb>modelValues(kIdx+1) & observedProb<=modelValues(kIdx));
                        below{bIdx,kIdx} = dists{bIdx,kIdx}((dists{bIdx,kIdx}<kIdx));                                                
                        % add the terms "above" to the dist 1 neighbors
                        histK{bIdx,kIdx} = numel(dists{bIdx,kIdx});
                        if kIdx ==1
                            dists{bIdx,kIdx} = [dists{bIdx,kIdx}, above{bIdx}];
                        end
                    end
                    
                end
            end
            
            for dIdx = obj.distToAnalyze
                eMat(:,:,dIdx) = eMat(:,:,dIdx)|di;
                for b1Idx = 1:size(obj.encounterMat,1)
                    % collect all beads at distance 1
                    inds1 = b1Idx+dists{b1Idx,dIdx};
                    inds1 = inds1(inds1<numel(obj.beadRange.bead2));
                    inds2 = b1Idx-dists{b1Idx,dIdx};
                    inds2 = inds2(inds2>=1);
                    eMat(b1Idx,[inds1 inds2],dIdx)= true;
                end
            end
            
            obj.connectivityMat = eMat;
%             obj.DisplayConnectivityGraph(eMat,above,obj.distToAnalyze,obj.beadsToAnalyze);
            
            %  create a chain from the graph
            obj.CreateChainFromConnectivityGraph;
            obj.DisplayChain;
        end
                                      
        function [expectedSignal,fitStructModel] = GetExpectedEncounterSignal(obj,encounterMat)
            % Get the expected encounter signal from an encounter matrix 
            expectedSignal    = obj.MeanIgnoreNaN(encounterMat);
            expectedSignal    = obj.smoother.Smooth(expectedSignal',obj.smoothingMethod,obj.smoothingSpan);
            se                = obj.SumIgnoreNaN(expectedSignal(:,1,1));% normalize
            expectedSignal    = expectedSignal(:,1,1)./se;
            [fitStructModel]  = fit((1:numel(expectedSignal))',expectedSignal,obj.model,obj.fitOpt);
        end        
        
        function GetDistanceDistribution(obj,dist)
            % calculate the distribution for a specifind distance
            f = figure;
            a = axes('Parent',f,'FontSize',30);
            for dIdx = 1:numel(dist)
                d     = obj.encounterMat(:,dist(dIdx));
                d     = d(~isnan(d));
                d     = d(d~=0);
                d     = (d-mean(d));
                s     = std(d);
                if s~=0
                    d=d./s;
                    
                    [v,e] = ecdf(d);
                    line('XData',e,...
                        'YData',v,...
                        'DisplayName',num2str(dist(dIdx)),...
                        'Color',rand(1,3),...
                        'LineWidth',4,...
                        'Parent',a);
                end
                
            end
            l=legend(get(a,'Children'));
            set(l,'FontSize',10);
            xlabel(a,'(Distance-\mu)/\sigma');
            ylabel(a,'CDF');
            
        end
        
        function DisplayConnectivityGraph(obj,eMat,above,distToAnalyze,beadToAnalyze)
            % construct a graph
            if ~exist('beadToAnalyze','var')
                beadToAnalyze = 1:size(eMat,1);
            end
            
            obj.connectivityMat         = triu(eMat(:,:,distToAnalyze));
%             inds                        = setdiff(1:size(eMat,1),beadToAnalyze);
%             obj.connectivityMat(inds,:) = false;
            % add nearest neighbor connectivity 
            obj.connectivityMat = obj.connectivityMat | diag(true(1,size(eMat,1)-1),1);
            obj.graph                   = biograph(obj.connectivityMat);
            set(obj.graph,'LayoutType','hierarchical','EdgeType','straight','NodeCallback',@obj.NodeCallback);
            
            % mark edges between nodes that have higher probability than nearest
            % neighbor with red
            for aIdx = 1:size(eMat,1)
                set(obj.graph.Nodes(aIdx),'Label',['Bead ' num2str(aIdx)]);
                for a1Idx = 1:numel(above{aIdx})
                    sourceNode = ['Node ' num2str(aIdx)];
                    if (aIdx +a1Idx)<=numel(obj.beadRange.bead2)
                        sinkNode =  ['Node ' num2str(aIdx+a1Idx)];
                    else
                        sinkNode = ['Node ' num2str(aIdx-a1Idx)];
                    end
                    
                    f = obj.graph.getedgesbynodeid(sourceNode,sinkNode);
                    set(f,'LineColor',[1 0 0]);
                end
            end
            view(obj.graph);
            
        end
        
        function CreateChainFromConnectivityGraph(obj)
            connectedBeads = obj.connectivityMat;
            % remove the trivial connections on the super diagonal        
            connectedBeads= triu(connectedBeads-diag(diag(connectedBeads,1),1));          
            [r,c]       = find(connectedBeads);    
            sr          = SimpleRouseParams;
            sr.numBeads = size(obj.encounterMat,1);                       
            sr.recordPath     = true;
            sr.numBeads       = numel(obj.beadRange.bead1);
            sr.dt             = 1e-2;
            sr.numSteps       = 500;
            sr.noiseSTD        = 0.0;
            sr.dimension       = 3;      
            sr.b               = sqrt(1);
            sr.diffusionConst  = 1;
            sr.numSimulations  = 1;
            sr.springConst     = -(sr.dimension* sr.diffusionConst* sr.dt/ sr.b^2)*ones( sr.numBeads); % can be a scalar or a matrix the size of (numBeads) X (numBeads)
            sr.connectedBeads  = [r c];
            obj.chain = SimpleRouse(sr);
            obj.chain.Initialize;
            obj.chain.Run;
            
        end
        
        function DisplayChain(obj)
            % display the connected chain 
            ChainDynamicsPlayer(obj.chain);
        end
        
    end
    
    methods (Access=private)
        
        function ProcessEncounterMatrix(obj,encounterMat)
            if ~exist('encounterMat','var')
                load(fullfile(obj.dataFolder,obj.dataFileName))
                [~,~,obj.encounterMat,~] = a.ProcessEncounters(obj.beadRange,'average');
                
            else
                obj.encounterMat    = encounterMat;
                obj.beadRange.bead1 = 1:size(encounterMat,1);
                obj.beadRange.bead2 = 1:size(encounterMat,2);
            end
            % Truncate the encounter matrix according to the bead range specified
            obj.encounterMat = obj.encounterMat(obj.beadRange.bead1,obj.beadRange.bead2-obj.beadRange.bead1(1)+1);
%             for bIdx = obj.beadRange.bead1
%                 obj.encounterMat(bIdx,:) = obj.InterpolateZeroValuesInSignal(obj.encounterMat(bIdx,:));
%             end
            s      = Smoother;
            k      = ones(3)*(1/7);
            k(1,1) = 0;
            k(3,3) = 0;
            s.Smooth(obj.encounterMat,obj.smoothingMethod,10,1);
            obj.encounterMat = s.signalOut;
            
            for bIdx=obj.beadRange.bead1
                obj.encounterMat(bIdx,:) = obj.InterpolateZeroValuesInSignal(obj.encounterMat(bIdx,:)); % interpolate zero values
                obj.encounterMat(bIdx,:)= obj.encounterMat(bIdx,:)./obj.SumIgnoreNaN(obj.encounterMat(bIdx,:)); % normalize to get probabilities 
            end
        end
        
        function [sigOut] = InterpolateZeroValuesInSignal(obj,sigIn)
            % remove nan values by interpolation of the signal
            sigOut = sigIn;
            s      = size(sigIn);
            if any(s(1:2)==1) % for 1D signal
                zeroInds   = find(sigIn==0 |isnan(sigIn));
                noZeroInds = find(~(sigIn==0) & ~isnan(sigIn));
                if ~isempty(zeroInds) && ~isempty(noZeroInds)
                    % Interpolate the signal in the nan positions
                    x     = noZeroInds;
                    y     = sigIn(x);
                    sigOut(zeroInds)= interp1(x,y,zeroInds,obj.zeroInterpolationMethod);% for the boundary values
                    % extrapolate the end values
                    
                    f =find(~isnan(sigOut),1,'first');
                    if f~=1
                        sigOut(1:f) = sigOut(f);
                    end
                    f= find(~isnan(sigOut),1,'last');
                    if f~=numel(sigOut)
                        sigOut(f:end) = sigOut(f);
                    end                                        
                end
            else
                %                 sigOut(isnan(sigIn))=0;
                [zeroInds(:,1), zeroInds(:,2)]     = find(sigOut==0);
                [noZeroInds(:,1), noZeroInds(:,2)] = find(~(sigIn==0) & ~isnan(sigIn));
                sigNoZero = sigIn(:);
                sigNoZero = sigNoZero (sigNoZero ~=0 & ~isnan(sigNoZero));
                if ~isempty(zeroInds)
                    % Interpolate the signal in the nan positions
                    %                     [x,y] = meshgrid(1:size(sigOut,1),1:size(sigOut,2));
                    intPoints = interp2(noZeroInds(:,2), noZeroInds(:,1),sigOut,zeroInds(:,2), zeroInds(:,1),obj.zeroInterpolationMethod);
                    s         = sub2ind(size(sigOut),zeroInds(:,1), zeroInds(:,2));
                    sigOut(s) = intPoints;
                end
            end
        end
        
        function [chainRingStruct] = AnalyzeEncounterAsRingsAndChains(obj,prob)
            % Seperate the encounter probability signal prob
            % into regions of chains, and rings. The decomposition is
            % defined by the position of the local maximas of the signal
            % prob.
            
            chainStruct  = struct('type',[],...
                'containedIn',[],...
                'startInd',[],...
                'endInd',[],...
                'equation',[],...
                'length',[],...
                'normalizationConst',[],...
                'containing',[]);
            ringStruct   = chainStruct;
            
            % Find local max in a signal
            [lMax]       = local_max(prob);
            
            % If index 1 exists in the local_max, remove it
            lMax = lMax(lMax~=1);
            
            % For each max point, find the first point of intersection to
            % its left on the probability signal curve
            
            % Start with all rings
            for lmIdx = 1:numel(lMax)
                % Match position of the NaNs in the signal
                x = 1:numel(prob);
                x(isnan(prob))= nan;
                
                intersections   = polyxpoly(x,prob,1:numel(prob), prob(lMax(lmIdx)).*ones(1,numel(prob)));
                intersections   = round(intersections); % round to get indices
                % Find the first intersection index to the left of the local max
                d               = find(intersections<lMax(lmIdx),1,'last');
                if isempty(d) && prob(intersections(1))>=max(prob(1:10))
                    d=1;
                end
                ringStruct(lmIdx).startInd  = intersections(d);
                ringStruct(lmIdx).endInd    = lMax(lmIdx);
                ringStruct(lmIdx).length    = lMax(lmIdx)-intersections(d);
                ringStruct(lmIdx).equation  = @(d,N,sig)(sig+(d./N).*(N-d)).^(-1.5); % where sig is the sigma for the containing structure
                ringStruct(lmIdx).type      = 'ring';
                ringStruct(lmIdx).normalizationConst = (sum(ringStruct(lmIdx).equation(1:ringStruct(lmIdx).length-1,ringStruct(lmIdx).length,0)));
            end
            
            % Sort by ring size
            [loopSize,inds] = sort([ringStruct.length],'descend');
            
            % Rearrange ring structures according to loop size
            ringStruct = ringStruct(inds);
            
            % Construct a matrix with a visual display of the loops
            loopChainMat = zeros(2*numel(ringStruct),numel(obj.beadRange.bead1));
            for lIdx = 1:numel(loopSize);
                loopChainMat(2*lIdx-1,ringStruct(lIdx).startInd:ringStruct(lIdx).endInd)=lIdx;
            end
            
            % Set the chain positions where there are no loops
            l = sum(loopChainMat);
            c = l==0;
            r = regionprops(c,'pixelList');
            
            % Expand the loopChainMat to allow chain insertion (+ 1 line
            % just to make sure there is no overlap)
            loopChainMat = [loopChainMat;2*zeros(numel(r)+1,size(loopChainMat,2))];
            
            for rIdx = 1:numel(r)
                chainStruct(rIdx).startInd = r(rIdx).PixelList(1,1);
                chainStruct(rIdx).endInd   = r(rIdx).PixelList(end,1);
                chainStruct(rIdx).equation = @(d,sig) (sig+d).^(-1.5); %where sig is the sigma of the containing structure
                chainStruct(rIdx).length   = chainStruct(rIdx).endInd-chainStruct(rIdx).startInd;
                chainStruct(rIdx).type     = 'chain';
                chainStruct(rIdx).normalizationConst = sum(chainStruct(rIdx).equation(1:chainStruct(rIdx).length,0));
                loopChainMat(end-2*rIdx+1,chainStruct(rIdx).startInd:chainStruct(rIdx).endInd) = numel(ringStruct)+rIdx;
            end
            
            % Find the correct ordering of loops and chains by labeling
            rp = regionprops(logical(loopChainMat),'PixelList');
            oMap = zeros(numel(rp),2);
            % first column is the order in the composite structure
            % second column is the index in the chainLoopMat
            for rIdx = 1:numel(rp)
                oMap(rIdx,1) = rIdx;
                oMap(rIdx,2) = loopChainMat(rp(rIdx).PixelList(1,2),rp(rIdx).PixelList(1,1));
            end
            % Create the mapping between the ring-chain segments and the
            % order of the composite structures
            chainRingStruct  = [ringStruct,chainStruct];
            chainRingStruct  = chainRingStruct(oMap(:,2));
%             rp = rp(oMap(:,1));
            % Assign the containning order
            lcMat = loopChainMat;
            for oIdx = 1:numel(oMap(:,2))
                lcMat(loopChainMat==oMap(oIdx,2))=oMap(oIdx,1);
            end
            loopChainMat = lcMat;
            for oIdx = 1:numel(oMap(:,2))
                containedIn = find(loopChainMat(1:rp(oIdx).PixelList(1,2)-1,rp(oIdx).PixelList(1,1)),1,'last');
                if ~isempty(containedIn)
                    chainRingStruct(oIdx).containedIn = loopChainMat(containedIn,rp(oIdx).PixelList(1,1));
                end
                
                ind = 1 ;
                for pIdx = 1:numel(rp(oIdx).PixelList(:,1))% go over all pixels of that structure and search downward for the first structure
                 containing = find(loopChainMat(rp(oIdx).PixelList(pIdx,2)+1:end,rp(oIdx).PixelList(pIdx,1)),1,'first');
                 if ~isempty(containing)
                  chainRingStruct(oIdx).containing(ind) = loopChainMat(rp(oIdx).PixelList(pIdx,2)+containing,rp(oIdx).PixelList(pIdx,1));
                  ind = ind+1;
                 end
                end
                 chainRingStruct(oIdx).containing= unique( chainRingStruct(oIdx).containing);
            end
        end
        
        function vals = GetCompositeFunctionVals(obj,chainRingStruct)
            % Calculate the values of the composite ring-chain structure;
            vals=[];
            for sIdx = 1:numel(chainRingStruct)
                % Evaluate each one of the functions
                
            end
        end
        
        function [dists, modelValues] = TransformProbToDist(obj,prob)
            % transform the probabilitiy observed into distances
            if strcmpi(obj.prob2distMethod,'fitModel')
                inds        = find(~isnan(prob));
                [fitStruct] = fit(inds',prob(inds)',obj.model,obj.fitOpt);
                beta        = fitStruct.beta;
                s           = sum(inds.^(-beta));
                modelValues = obj.model(beta,inds);
                modelValues = modelValues./modelValues(1) *max(prob(1:10));
                dists       = (prob *s).^(-1./beta);
            elseif strcmpi(obj.prob2distMethod,'rouse')
                beta        = 1.5;
                inds        = find(~isnan(prob));
                s           = sum(inds.^(-beta));
                modelValues = obj.model(beta,inds);
                modelValues = modelValues./modelValues(1) *max(prob(1:10));
                dists       = (prob *s).^(-1./beta);
            elseif strcmpi(obj.prob2distMethod,'composite')
            end
        end
        
        function NodeCallback(obj,varargin)
            disp('node')
            
            node = varargin{1};
            if strcmpi(node.UserData,'On')
                node.UserData = 'Off';
                nodeColor = [1 1 0.7000];
            else
                node.UserData = 'On';
                nodeColor = [0 1 0];
            end
            a = node.getancestors;
            d = node.getdescendants;
            for aIdx = 1:numel(a);
                a(aIdx).Color = nodeColor;
                a(aIdx).hgUpdate;
            end
            
            for dIdx = 1:numel(d)
                d(dIdx).Color=nodeColor;
                d(dIdx).hgUpdate;
            end
        end
        
        function [observedProb] = ProcessBeadEncounterSignal(obj,encounterSignal)
            % process a single encounter signal
            % fill NaN position with nearest neighbors mean value
            observedProb = obj.InterpolateZeroValuesInSignal(encounterSignal);
            observedProb = obj.smoother.Smooth(observedProb,obj.smoothingMethod,obj.smoothingSpan);
            %             observedProb = obj.SmoothSignal(observedProb,...
            %                                             obj.smoothingSpan,obj.smoothingMethod);
            sop            = obj.SumIgnoreNaN(observedProb(1,:,end));
            observedProb   = observedProb(1,:,end)./sop; % normalize
        end
    end
    
    methods (Static)
        
        function m = MeanIgnoreNaN(sigIn)
            sigIn(isnan(sigIn)) = 0;
            m = mean(sigIn);
            m = m./sum(m);
        end
        
        function s = SumIgnoreNaN(sigIn)
            % calculate the sum of an input signal without the NaNs
               s  = sum(sigIn(~isnan(sigIn)));
        end
        
        function PlotBeadClusteringByDistance(observedProb,inds, k)
            figure,
            plot(inds,observedProb,'bo-',1:numel(k),k,'r','Linewidth',4,'MarkerSize',6),
            set(gca,'FontSize',35,'NextPlot','Add');%,'XScale','log','YScale','log'),
            xlabel('Distance [beads]'),
            ylabel('encoutner Prob.')
            
            % add patches to represent the  distance by probability, given the model
            cMap = rand(numel(inds),3);
            for kIdx = 1:numel(inds)-1
                patch([inds(1) inds(end), inds(end), inds(1)], [k(kIdx) k(kIdx), k(kIdx+1), k(kIdx+1)],...
                    'r','FaceAlpha',0.25,'FaceColor',cMap(kIdx,:));
            end
            set(gca,'XLim',[1 inds(end)])
        end
        
        function sigOut = SmoothSignal(sigIn,smoothSpan,method)%obsolete
            % Smooth a signal sigIn with a smoothing span smoothSpan
            % try all smoothing spans defing in the parameter smoothiSpan
            ind    = 1;
            sigOut = zeros(1,numel(sigIn),numel(smoothSpan));
            for s = smoothSpan
            sigOut(1,:,ind) = smooth(sigIn,s,method);
            ind = ind+1;
            end
        end
    end
    
end