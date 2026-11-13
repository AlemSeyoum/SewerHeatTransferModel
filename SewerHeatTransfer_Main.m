tic; clc; clear; close all; format long

%% ================================================================
%% 0) USER CONTROLS: SIMULATION MODE + EXPORT TAG
%% ================================================================
% Choose one:
%   "availability"  = heat availability simulation; no heat is extracted
%   "extraction"    = heat extraction simulation; heat is removed at HexPipes

simulationMode = "extraction";     % change to "extraction" when needed

exportTag = "Feb";

doAvailability = strcmpi(simulationMode, "availability");
doExtraction   = strcmpi(simulationMode, "extraction");

if ~(doAvailability || doExtraction)
    error('simulationMode must be either "availability" or "extraction".'); % error handling
end

%% ================================================================
%% 1) CREATE OUTPUT FOLDER
%% ================================================================
if doAvailability
    outputFolder = sprintf('HeatAvailability_%s', exportTag);
else
    outputFolder = sprintf('HeatExtraction_%s', exportTag);
end

origFolder = pwd;

if ~exist(outputFolder,'dir')
    mkdir(outputFolder);
end


fprintf('Results will be written to: %s\n', outputFolder);

%% ================================================================
%% 2) LOAD LINK AND NODE OBJECT FILES 
%% ================================================================

% ---- Conduits + Nodes (contains hw_conduit and hw_node) ----
load('PeterBrConduits&Nodes_17K');  % provides: dataTypeHeader, dataHeader, dataUnitHeader, data
dataTypeHeader_CN = dataTypeHeader; % CN refres conduit and Node
dataHeader_CN     = dataHeader;
data_CN           = data;

% ---- Other link element files (each contains one table in same structure) ----
load('PeterBr_pump_17K');      dataHeader_pump    = dataHeader; data_pump    = data;
load('PeterBr_weir_17K');       dataHeader_weir    = dataHeader; data_weir    = data;
load('PeterBr_orifice_17K');    dataHeader_orifice = dataHeader; data_orifice = data;
load('PeterBr_flap_valve_17K');  dataHeader_flap    = dataHeader; data_flap    = data;
load('PeterBr_sluice_17K');     dataHeader_sluice  = dataHeader; data_sluice  = data;
load('PeterBr_screen_17K');     dataHeader_screen  = dataHeader; data_screen  = data;
load('PeterBr_user_control_17K');     dataHeader_usercontrol  = dataHeader; data_usercontrol  = data;

%% ================================================================
%% 3) EXTRACT CONDUIT + NODE TABLE FROM CN FILE
%% ================================================================
conduitDataIndex = strcmpi(dataTypeHeader_CN, 'hw_conduit');
nodeDataIndex    = strcmpi(dataTypeHeader_CN, 'hw_node');

if ~any(conduitDataIndex)
    error("hw_conduit table not found in PeterBrConduits&Nodes_17K");
end
if ~any(nodeDataIndex)
    warning("hw_node table not found in PeterBrConduits&Nodes_17K (continuing).");
end

conduitHeader = dataHeader_CN{conduitDataIndex};
conduitTable  = data_CN{conduitDataIndex};
% nodeHeader  = dataHeader_CN{nodeDataIndex};
% nodeTable   = data_CN{nodeDataIndex};

%% ================================================================
%% 3) HYDRAULIC TIME SERIES
%% ================================================================
load('PeterBr_ds_depth_17K'); pipe_header = header; Dds = data(:,2:end);
load('PeterBr_ds_flow_17K');  Qds = data(:,2:end);           % m3/s
load('PeterBr_ds_vel_17K');   Vds = data(:,2:end);

load('PeterBr_us_depth_17K'); Dus = data(:,2:end);
load('PeterBr_us_flow_17K');  Qus = data(:,2:end);           % m3/s
load('PeterBr_us_vel_17K');   Vus = data(:,2:end);

[m, numberOfPipes] = size(Qus); % m refers to time


%% ================================================================
%% 4) SUBCATCHMENT FLOWS
%% ================================================================
load('PeterBr_qfoul_17K');  subcm_header = header; qfoul  = data(:,2:end);
load('PeterBr_qtrade_17K');                   qtrade = data(:,2:end);


%% ================================================================
%% 5) REPEAT TIME-DEPENDENT INPUTS INTERNALLY
% Repeat hydraulic data to allow sewer temperatures to stabilise 
%% ================================================================
m0 = m;          % original duration (e.g. 48 h)
nCycles = 2;     % total run = 2 × 48 = 96h % one cycle is 48 hrs

Qus    = repmat(Qus,    nCycles, 1);
Qds    = repmat(Qds,    nCycles, 1);
Dus    = repmat(Dus,    nCycles, 1);
Dds    = repmat(Dds,    nCycles, 1);
Vus    = repmat(Vus,    nCycles, 1);
Vds    = repmat(Vds,    nCycles, 1);

qfoul  = repmat(qfoul,  nCycles, 1);
qtrade = repmat(qtrade, nCycles, 1);


% update simulation length
m = size(Qus,1);

fprintf('Simulation extended from %d h to %d h using %d repeated cycles.\n', ...
    m0, m, nCycles);


%% ================================================================
%% 6) TOPOLOGY / ORDER (SAFE ALIGNMENT)
%% ================================================================

load('PeterBrCalcorder_17K');    
% Expected variables in file:
%   linkListHeader  - link names
%   usLinkIndex     - upstream pipe index vectors

%% ================================================================
%% 7) DEFINE ID CLEANER  (KEEP .1/.2 SUFFIX)
%% ================================================================
cleanIDs = @(x) strtrim( erase(string(x), "!") ); % Remove '!' and extra spaces from IDs

% Hydraulic link IDs (master list from flow file)
pipe_header = cleanIDs(string(pipe_header(2:end))');   % (N x 1) % Clean hydraulic link IDs and convert to column vector

numberOfPipes = numel(pipe_header);

%% ================================================================
%% 8) ALIGN TOPOLOGY WITH HYDRAULIC ORDER
%% ================================================================

topoNames = cleanIDs(string(linkListHeader));

% --- Check size consistency ---
if numel(usLinkIndex) ~= numel(topoNames)  % Check consistency between upstream-link indices and topology link names
    error('Mismatch inside Calcorder file: linkListHeader and usLinkIndex sizes differ.');
end

[isFound, locTopo] = ismember(pipe_header, topoNames);% Match hydraulic link IDs to topology link IDs and return their positions

if any(~isFound)
    missing = pipe_header(~isFound);
    fprintf('\nERROR: The following hydraulic links are not found in Calcorder file:\n');
    disp(missing);
    error('Topology alignment failed.');
end

% ================================================================
% Reorder usLinkIndex cells to hydraulic order
% ================================================================
usLinkIndex_topo = usLinkIndex;          % original topology-order cell array
usLinkIndex = usLinkIndex_topo(locTopo); % cells now match hydraulic order

% ================================================================
% IMPORTANT: remap the stored upstream indices from topology order
% to hydraulic order
% topo index -> hydraulic index
% ================================================================
topoToHyd = zeros(numel(topoNames),1);
topoToHyd(locTopo) = 1:numberOfPipes;

usLinkIndex_hyd = cell(numberOfPipes,1);

for I = 1:numberOfPipes
    ups_topo = usLinkIndex{I};

    if isempty(ups_topo)
        usLinkIndex_hyd{I} = [];
    else
        usLinkIndex_hyd{I} = topoToHyd(ups_topo(:))';
    end
end

usLinkIndex = usLinkIndex_hyd;

% --- Final safety check ---
if numel(usLinkIndex) ~= numberOfPipes
    error('Topology size does not match hydraulic size after alignment.');
end

fprintf('Topology successfully aligned with hydraulic order, including upstream-index remap.\n');


%% ================================================================
%% 9) BUILD LINK IDs FROM OBJECT TABLES: link_id = us_node_id + link_suffix
%% ================================================================
buildIDs_us_suffix = @(hdr, tbl) build_ids_impl(hdr, tbl, cleanIDs);

conduitIDs = buildIDs_us_suffix(conduitHeader, conduitTable);
pumpIDs    = buildIDs_us_suffix(dataHeader_pump,    data_pump);
weirIDs    = buildIDs_us_suffix(dataHeader_weir,    data_weir);
orificeIDs = buildIDs_us_suffix(dataHeader_orifice, data_orifice);
flapIDs    = buildIDs_us_suffix(dataHeader_flap,    data_flap);
sluiceIDs  = buildIDs_us_suffix(dataHeader_sluice,  data_sluice);
screenIDs  = buildIDs_us_suffix(dataHeader_screen,  data_screen);
usercontrolIDs  = buildIDs_us_suffix(dataHeader_usercontrol,  data_usercontrol);

%% ================================================================
%% 10) CLASSIFY EACH HYDRAULIC LINK COLUMN BY TYPE
% Unrecognised link types are assigned "unknown" and treated as adiabatic
% (No heat exchange with air or soil is calculated)
%% ================================================================
linkType = strings(1, numberOfPipes);
for I = 1:numberOfPipes
    id = pipe_header(I);
    if any(conduitIDs == id)
        linkType(I) = "hw_conduit";
    elseif any(pumpIDs == id)
        linkType(I) = "hw_pump";
    elseif any(weirIDs == id)
        linkType(I) = "hw_weir";
    elseif any(orificeIDs == id)
        linkType(I) = "hw_orifice";
    elseif any(flapIDs == id)
        linkType(I) = "hw_flap_valve";
    elseif any(sluiceIDs == id)
        linkType(I) = "hw_sluice";
     elseif any(screenIDs == id)
        linkType(I) = "hw_screen";
     elseif any(usercontrolIDs == id)
        linkType(I) = "hw_user_control";
    else
        linkType(I) = "unknown";
    end
end

isConduit = (linkType == "hw_conduit");
fprintf('Total links: %d | Conduits: %d | Non-conduits: %d | Unknown: %d\n', ...
    numberOfPipes, sum(isConduit), sum(~isConduit), sum(linkType=="unknown"));

if any(linkType=="unknown")
    warning("Some hydraulic links were not found in any object table. They will be treated as non-conduit (adiabatic).");
end

%% ================================================================
%% 11) MAP CONDUIT PROPERTIES TO HYDRAULIC ORDER (ONLY FOR CONDUITS)
%% ================================================================
% ---- Diameter / Radius ----
widthIndex = strcmpi(conduitHeader, 'conduit_width');
rawWidth   = conduitTable(:, widthIndex);
D_mm       = cellfun(@(x) str2double(string(x)), rawWidth); % Convert conduit widths from cell array to numeric diameters (mm)
R_c        = D_mm/2000;                                     % m (radius)

% ---- Length ----

LengthIndex = strcmpi(conduitHeader, 'conduit_length');
rawL        = conduitTable(:, LengthIndex);
L_c         = cellfun(@(x) str2double(string(x)), rawL);    % m

% ---- Material / Shape ----
MaterialsIndex = strcmpi(conduitHeader, 'conduit_material');
Materials_c    = conduitTable(:, MaterialsIndex);

ShapesIndex = strcmpi(conduitHeader, 'shape');
Shapes_c    = conduitTable(:, ShapesIndex);

% ---- Thickness ----% Pipe wallthickness not found in Infoworks and User shall provide this.
wallThicknessIndex = strcmpi(conduitHeader, 'user_number_2'); 
rawT = conduitTable(:, wallThicknessIndex);
t_mm = cellfun(@(x) str2double(string(x)), rawT);           % mm
t_c  = t_mm./1000;                                          % m

% Build conduitIDs already computed; now find row mapping:
% For each hydraulic link, return the corresponding row in the conduit table (0 if the link is not a conduit)
[~, locConduitRow] = ismember(pipe_header, conduitIDs); % locConduitRow(I)=row in conduit table (0 if not conduit)

% Allocate full arrays sized to hydraulic columns
R      = zeros(1, numberOfPipes);
L      = zeros(1, numberOfPipes);
t      = ones(1, numberOfPipes);         % Placeholder values (non-conduits are treated adiabatically)
kp     = ones(1, numberOfPipes);         % Placeholder values (not used for non-conduits)
Shapes = repmat({'C'}, 1, numberOfPipes);

% Fill conduits only
for I = find(isConduit)
    row = locConduitRow(I);
    if row <= 0
        % Shouldn't happen if isConduit was set by conduitIDs, but keep safe:
        continue;
    end
    R(I) = R_c(row);
    L(I) = L_c(row);
    t(I) = t_c(row);
    Shapes{I} = Shapes_c{row};
end

%% ================================================================
%% 12) PIPE THERMAL CONDUCTIVITY kp (CONDUITS ONLY)
%% ================================================================
for I = find(isConduit)
    row = locConduitRow(I);
    mat = upper(strtrim(string(Materials_c{row})));
    switch mat
        case {"BR","BRICK"}                  , kp(I) = 0.8;   % Brick
        case "CI"                            , kp(I) = 50.0;  % Cast Iron
        case {"CO","CP","CW","CONCRETE"}     , kp(I) = 1.7;   % Concrete
        case "DI"                            , kp(I) = 45.0;  % Ductile Iron
        case {"HPPE","HDPE"}                 , kp(I) = 0.42;  % HDPE
        case "MDPE"                          , kp(I) = 0.40;  % MDPE
        case "PF"                            , kp(I) = 0.25;  % Pitch Fibre
        case "PLA"                           , kp(I) = 0.20;  % Generic Plastic
        case "PVC"                           , kp(I) = 0.17;  % PVC
        case {"SWC","VC"}                    , kp(I) = 1.2;   % Stoneware/Vitrified Clay
        case {"U","UNKN","UNKNOWN"}          , kp(I) = 1.0;   % Unknown
        otherwise                            , kp(I) = 1.0;   % Default
    end
end
%% ========================================================================
%% 13)FUNCTION TO EXTRACT NODES
% Extract upstream and downstream node IDs for all links
% Used for infiltration mapping, exports, and network connectivity/diagnostics
%% ========================================================================
getUSnode = @(hdr,tbl) string(tbl(:, strcmpi(hdr,'us_node_id')));
getDSnode = @(hdr,tbl) string(tbl(:, strcmpi(hdr,'ds_node_id')));

% Build node lists aligned to hydraulic order
pipeUSnode = strings(numberOfPipes,1);
pipeDSnode = strings(numberOfPipes,1);

% --- Conduits ---
us_conduit = getUSnode(conduitHeader, conduitTable);
ds_conduit = getDSnode(conduitHeader, conduitTable);
[~,locC] = ismember(pipe_header, conduitIDs);

for I = find(isConduit)
    pipeUSnode(I) = cleanIDs(us_conduit(locC(I)));
    pipeDSnode(I) = cleanIDs(ds_conduit(locC(I)));
end

% --- Pumps ---
us_pump = getUSnode(dataHeader_pump, data_pump);
ds_pump = getDSnode(dataHeader_pump, data_pump);
[~,locP] = ismember(pipe_header, pumpIDs);

for I = find(linkType=="hw_pump")
    pipeUSnode(I) = cleanIDs(us_pump(locP(I)));
    pipeDSnode(I) = cleanIDs(ds_pump(locP(I)));
end

% --- Weirs ---
us_weir = getUSnode(dataHeader_weir, data_weir);
ds_weir = getDSnode(dataHeader_weir, data_weir);
[~,locW] = ismember(pipe_header, weirIDs);

for I = find(linkType=="hw_weir")
    pipeUSnode(I) = cleanIDs(us_weir(locW(I)));
    pipeDSnode(I) = cleanIDs(ds_weir(locW(I)));
end

% --- Orifices ---
us_orifice = getUSnode(dataHeader_orifice, data_orifice);
ds_orifice = getDSnode(dataHeader_orifice, data_orifice);
[~,locO] = ismember(pipe_header, orificeIDs);

for I = find(linkType=="hw_orifice")
    pipeUSnode(I) = cleanIDs(us_orifice(locO(I)));
    pipeDSnode(I) = cleanIDs(ds_orifice(locO(I)));
end

% --- Flap valves ---
us_flap = getUSnode(dataHeader_flap, data_flap);
ds_flap = getDSnode(dataHeader_flap, data_flap);
[~,locF] = ismember(pipe_header, flapIDs);

for I = find(linkType=="hw_flap_valve")
    pipeUSnode(I) = cleanIDs(us_flap(locF(I)));
    pipeDSnode(I) = cleanIDs(ds_flap(locF(I)));
end

% --- Sluice ---
us_sluice = getUSnode(dataHeader_sluice, data_sluice);
ds_sluice = getDSnode(dataHeader_sluice, data_sluice);
[~,locS] = ismember(pipe_header, sluiceIDs);

for I = find(linkType=="hw_sluice")
    pipeUSnode(I) = cleanIDs(us_sluice(locS(I)));
    pipeDSnode(I) = cleanIDs(ds_sluice(locS(I)));
end

% --- Screens ---
us_screen = getUSnode(dataHeader_screen, data_screen);
ds_screen = getDSnode(dataHeader_screen, data_screen);
[~,locS] = ismember(pipe_header, screenIDs);

for I = find(linkType=="hw_screen")
    pipeUSnode(I) = cleanIDs(us_screen(locS(I)));
    pipeDSnode(I) = cleanIDs(ds_screen(locS(I)));
end

% --- User Control ---
us_usercontrol = getUSnode(dataHeader_usercontrol, data_usercontrol);
ds_usercontrol = getDSnode(dataHeader_usercontrol, data_usercontrol);
[~,locS] = ismember(pipe_header, usercontrolIDs);

for I = find(linkType=="hw_user_control")
    pipeUSnode(I) = cleanIDs(us_usercontrol(locS(I)));
    pipeDSnode(I) = cleanIDs(ds_usercontrol(locS(I)));
end

%% ========================================================================
%% 14) EXTRACT LINK ATTRIBUTES (ALL LINK TYPES)
%Used mainly to populate metadata fields in exported results tables
%% ========================================================================

% ---------- Initialise arrays ----------
system_type      = strings(numberOfPipes,1);
asset_id         = strings(numberOfPipes,1);
conduit_length   = nan(numberOfPipes,1);
shape            = strings(numberOfPipes,1);
conduit_width    = nan(numberOfPipes,1);
conduit_height   = nan(numberOfPipes,1);
conduit_material = strings(numberOfPipes,1);
gradient         = nan(numberOfPipes,1);

% ---------- Helper function ----------
getVal = @(hdr,tbl,row,name) ...
    string(tbl{row, strcmpi(hdr,name)});

getNum = @(hdr,tbl,row,name) ...
    str2double(string(tbl{row, strcmpi(hdr,name)}));

hasField = @(hdr,name) any(strcmpi(hdr,name));

% ---------- Define all link groups ----------
linkGroups = {
    conduitIDs, conduitHeader, conduitTable, "hw_conduit";
    pumpIDs, dataHeader_pump, data_pump, "hw_pump";
    weirIDs, dataHeader_weir, data_weir, "hw_weir";
    orificeIDs, dataHeader_orifice, data_orifice, "hw_orifice";
    flapIDs, dataHeader_flap, data_flap, "hw_flap_valve";
    sluiceIDs, dataHeader_sluice, data_sluice, "hw_sluice";
    screenIDs, dataHeader_screen, data_screen, "hw_screen";
    usercontrolIDs, dataHeader_usercontrol, data_usercontrol, "hw_user_control"
};

% ---------- Loop through all link types ----------
for g = 1:size(linkGroups,1)

    IDs   = linkGroups{g,1};
    hdr   = linkGroups{g,2};
    tbl   = linkGroups{g,3};
    typeN = linkGroups{g,4};

    [~,loc] = ismember(pipe_header, IDs);

    idx = find(linkType == typeN);

    for k = 1:numel(idx)
        I = idx(k);
        row = loc(I);

        if row <= 0
            continue
        end

        % ---- system_type ----
        if hasField(hdr,'system_type')
            system_type(I) = cleanIDs(getVal(hdr,tbl,row,'system_type'));
        end

        % ---- asset_id ----
        if hasField(hdr,'asset_id')
            asset_id(I) = cleanIDs(getVal(hdr,tbl,row,'asset_id'));
        end

        % ---- conduit_length ----
        if hasField(hdr,'conduit_length')
            conduit_length(I) = getNum(hdr,tbl,row,'conduit_length');
        end

        % ---- shape ----
        if hasField(hdr,'shape')
            shape(I) = cleanIDs(getVal(hdr,tbl,row,'shape'));
        end

        % ---- conduit_width ----
        if hasField(hdr,'conduit_width')
            conduit_width(I) = getNum(hdr,tbl,row,'conduit_width');
        end

        % ---- conduit_height ----
        if hasField(hdr,'conduit_height')
            conduit_height(I) = getNum(hdr,tbl,row,'conduit_height');
        end

        % ---- conduit_material ----
        if hasField(hdr,'conduit_material')
            conduit_material(I) = cleanIDs(getVal(hdr,tbl,row,'conduit_material'));
        end

        % ---- gradient ----
        if hasField(hdr,'gradient')
            gradient(I) = getNum(hdr,tbl,row,'gradient');
        end

    end
end


%% ========================================================================
%% 15. INFILTRATION (ALL LINK TYPES)
%% ========================================================================
% ------------------------------------------------------------
% Load infiltration time series
% ------------------------------------------------------------
load('PeterBr_node_infiltration_17K');  % header + data
inf_header = header;
Qinf_nodes = cellfun(@(x) str2double(string(x)), data(:,2:end));

Qinf_nodes = repmat(Qinf_nodes, nCycles, 1);

inf_nodes  = cleanIDs(string(inf_header(2:end))');

nInf = numel(inf_nodes);


% Build mapping: infiltration node → outgoing links (ALL types)
% ------------------------------------------------------------
outPipesOfInfNode = cell(nInf,1);

for kk = 1:nInf
    outPipesOfInfNode{kk} = find(pipeUSnode == inf_nodes(kk));
end

Tinf = 9;   % °C infiltration temperature

fprintf('Infiltration mapping built for ALL link types.\n');


%% ================================================================
%% 16) BASIC MODEL SETTINGS
%% ================================================================
Mesh = 500;


%% ================================================================
%% 17) SOURCE LINKS & SUBCATCHMENT MAPPING
%% ================================================================

% Identify source links, i.e. links with no upstream connections
isSource = cellfun(@isempty, usLinkIndex);

% Match hydraulic link IDs to subcatchment IDs
pipe_header_sc = pipe_header;   % Hydraulic link IDs, already cleaned

subcm_header = string(subcm_header(2:end))';
subcm_header = cleanIDs(subcm_header);

[~, SubcmPipeIndex] = ismember(pipe_header_sc, subcm_header);

% SubcmPipeIndex(I) gives the column index of the matching subcatchment for link I
% A value of 0 means no matching subcatchment was found

% Count how many links are associated with each subcatchment.
% This is used later to divide subcatchment inflows among multiple links.

validSC = SubcmPipeIndex(SubcmPipeIndex > 0);   % Exclude links with no subcatchment match

if isempty(validSC)
    scCounts = [];                              % No subcatchment assignments found
else
    nSC = max(validSC);                         % Total number of subcatchment columns

    scCounts = accumarray(validSC, 1, [nSC 1]);
    % scCounts(sc) = number of links sharing subcatchment sc
end


%% ================================================================
%% 18) TEMPERATURE ASSUMPTIONS
%% ================================================================

[r1, c1] = size(qfoul);

% In-sewer air temperature
% ------------------------------------------------
Ta = 7 * ones(m, numberOfPipes);

% Soil temperature
% ------------------------------------------------
SoilTemp = 9 * ones(m, numberOfPipes);

% ------------------------------------------------
% Load measured foul temperature profile
% ------------------------------------------------
tblF = readtable('WastewaterTemperature_Feb.csv');

Tfoul_src = tblF{:,2};          % column 2 = temperature

% if column is cell (common when csv contains text)
if iscell(Tfoul_src)
    Tfoul_src=str2double(Tfoul_src);
end

Tfoul_src = Tfoul_src(:);% Ensure column vector

Tfoul_src = double(Tfoul_src);  % ensure numeric 

% ------------------------------------------------
% Approximate trade temperature profile
% (assume trade wastewater is ~2 °C warmer)
% ------------------------------------------------
Ttrade_src = Tfoul_src + 2;
Ttrade_src =Ttrade_src(:);

Tfoul_src  = repmat(Tfoul_src,  nCycles, 1);  % Repeat measured temperature profile to match repeated hydraulic cycles
Ttrade_src = repmat(Ttrade_src, nCycles, 1);  % Repeat trade temperature profile consistently with qtrade

% Check length consistency with model timesteps
if length(Tfoul_src) ~= m || length(Ttrade_src) ~= m
    error('Measured temperature profiles must match model timestep length (m).');
end


% Tw0: Temperature entering source pipes
% ------------------------------------------------
Tw0 = nan(m, numberOfPipes);

sourcePipes=find(isSource);% indices of source pipes

for k = 1:length(sourcePipes)
    I = sourcePipes(k); % actual pipe index in the full network
    sc = SubcmPipeIndex(I);
    
    if sc <= 0 
        % Fallback if pipe has no subcatchment mapping
        Tw0(:,I) = Tfoul_src;
        continue
    end

    % Foul and trade inflows associated with this subcatchment
    qf = qfoul(:, sc);
    qt = qtrade(:, sc);
    
    qf=qf(:);% Ensure column vector
    qt=qt(:);% Ensure column vector

    qtot = qf + qt;
    qtot(qtot <= 0) = 1e-9;   % avoid division by zero

    % Flow-weighted temperature
    Tw0(:,I) = (qf .* Tfoul_src + qt .* Ttrade_src) ./ qtot;

end

Tfoul  = repmat(Tfoul_src, 1, c1);  % (m x c1) % Replicate foul temperature profile for all subcatchments
Ttrade = repmat(Ttrade_src, 1, c1); % (m x c1) % Replicate trade temperature profile for all subcatchments


%% ================================================================
%% 19) CONSTANTS
%% ================================================================
rho = 1000;     % kg/m3
cp  = 4200;     % J/kg.K
ua  = 0.13;     % In-sewer air velocity(m/s)

%% ================================================================
%% 20) MULTI-PIPE HEAT EXTRACTION SETUP 
%% ================================================================
% In availability mode, extraction is disabled automatically.
% In extraction mode, edit HexPipes, HexPowerRequested and TminHex below.

if doExtraction

    % ------------------------------------------------------------
    % Extraction pipe selection
    % ------------------------------------------------------------
    % HexPipes are internal hydraulic column indices, not text LinkIDs.
    % Add as many extraction pipes as required.
    %
    % Example for multiple extraction pipes:
    HexPipes = [10009 6715];

    %HexPipes = [16008];

    nHex = numel(HexPipes);

    % ------------------------------------------------------------
    % Requested extraction power [W]
    % ------------------------------------------------------------
    % HexPowerRequested has size m x nHex:
    %   rows    = timesteps
    %   columns = extraction pipes
    %
    % This allows constant or time-varying extraction demand.

    HexPowerRequested = zeros(m, nHex);

    % Constant requested extraction power
    %HexPowerRequested(:,1) = 5e6;   % Pipe 14431requests 4 MW

    % Example for multiple extraction pipes:
    HexPowerRequested(:,1) = 5e6;   % Pipe 10009 requests 3 MW
    HexPowerRequested(:,2) = 5e6;   % Pipe 6715 requests 2 MW

    % If heat pump capacity data are available, this could be replaced by:
    % HexPowerRequested = HeatPumpCapacity;

    % ------------------------------------------------------------
    % Minimum allowed temperature after extraction [°C]
    % ------------------------------------------------------------
    % One Tmin value is required for each extraction pipe.
    %
    % Example for multiple extraction pipes:
    TminHex = [5 5];

    %TminHex = [5];

else

    % No extraction during heat availability simulation
    HexPipes = [];
    nHex = 0;
    HexPowerRequested = zeros(m, 0);
    TminHex = [];

end

%% ================================================================
%% 21) FILTERING / FLOORS (UNCHANGED)
%Apply small numerical floors to avoid zero-flow and zero-depth conditions
% that can cause divide-by-zero errors and unstable heat-transfer calculations
%% ================================================================

%Qds(Qds<0.00065*4) = 0.00065*4;
%Qus(Qus<0.00065*4) = 0.00065*4;
Qmin = 1e-5;
Qds(Qds < Qmin) = Qmin;
Qus(Qus < Qmin) = Qmin;

qfoul(qfoul<1e-5)  = 1e-5;
qtrade(qtrade<1e-5)= 1e-5;
Dus(Dus<1e-5)      = 1e-5;
Dds(Dds<1e-5)      = 1e-5;
Vus(Vus<1e-5)      = 1e-5;
Vds(Vds<1e-5)      = 1e-5;

%% ================================================================
%% 22) TOPOLOGICAL ORDER
% Sort links so upstream links are processed before downstream links
%% ================================================================
topoOrder = topo_sort_from_usLinkIndex(usLinkIndex, numberOfPipes);

%% ================================================================
%% 23) HEAT TRANSFER COEFFICIENT PARAMETERS 
%% ================================================================
fc   = zeros(1,numberOfPipes);% fc-calibrating factor
ksds = zeros(1,numberOfPipes); % ds: soil penetration depth & ks: soil thermal conductivity

Qmean = mean(Qus, 1);
for I = 1:numberOfPipes
    Qref = Qmean(I);
    if Qref < 0.01
        fc(I) = 44;     ksds(I) = 67; 
    elseif Qref > 0.09
        fc(I) = 236;   ksds(I) = 100;
    else
        fc(I)   = 44 + (236-44)*(Qref-0.01)/(0.09-0.01);
        ksds(I) = 67 + (100-67) *(Qref-0.01)/(0.09-0.01); 
       
    end
end

%% ================================================================
%% 24) OUTPUT STORAGE 
%% ================================================================
Tw_in_before = nan(m, numberOfPipes);  % inlet before extraction (junction mixing or Tw0)
Tw_in_after  = nan(m, numberOfPipes);  % inlet after extraction
Tw_out       = nan(m, numberOfPipes);  % outlet after losses along pipe

% Heat extraction results (rows = timesteps, columns = extraction pipes)
TinDrop           = zeros(m, numel(HexPipes));   % Actual temperature reduction [°C]
HexPowerExtracted = zeros(m, numel(HexPipes));   % Actual extracted heat/power [W]

% For longest path profile plot (choose which timestep snapshot you want)
plotTimeIndex = m;% use last timestep by default
Tw_mesh_plot  = nan(numberOfPipes, Mesh+1);
Tw_mesh_plot_time = nan(m, numberOfPipes, Mesh+1);

%% ================================================================
%% 25) INITIALIZATION (t = 1)
%% ================================================================

jT_init = 1;   % First simulation timestep

% Initialise wastewater temperatures throughout the network.
% Source-link temperatures are assigned from subcatchment inflows and
% temperatures are routed downstream in topological order.
if doAvailability

    [Tw_in_before, Tw_out, Tw_mesh_plot] = init_temperature_state_opportunity( ...
        Tw_in_before, Tw_out, Tw_mesh_plot, ...
        topoOrder, isSource, usLinkIndex, SubcmPipeIndex, scCounts, ...
        Tw0, Tfoul, Ttrade, qfoul, qtrade, ...
        Qds, Qus, Vus, Dus, ...
        Shapes, R, L, Mesh, ...
        kp, t, ksds, fc, Ta, SoilTemp, ...
        rho, cp, ...
        jT_init, plotTimeIndex);

    Tw_in_after(1,:) = Tw_in_before(1,:);   % no extraction in availability mode

else

    [Tw_in_before, Tw_in_after, Tw_out] = init_temperature_state( ...
        Tw_in_before, Tw_in_after, Tw_out, ...
        topoOrder, isSource, usLinkIndex, SubcmPipeIndex, scCounts, ...
        Tw0, Tfoul, Ttrade, qfoul, qtrade, ...
        Qds, Qus, Vus, Dus, ...
        Shapes, R, L, Mesh, ...
        kp, t, ksds, fc, Ta, SoilTemp, ...
        rho, cp, ...
        HexPipes, HexPowerRequested, TminHex, ...
        jT_init );

end

% Replace any remaining undefined outlet temperatures with the
% measured foul temperature at the first timestep
Tw_out(1, isnan(Tw_out(1,:))) = Tfoul_src(1);

% Store initial longitudinal temperature profiles for plotting
Tw_mesh_plot_time(1,:,:) = Tw_mesh_plot;

% Diagnostic check: number of NaN temperatures after initialization
sum(isnan(Tw_out(1,:)))

%% ================================================================
%% 26) MAIN TRANSIENT TIME LOOP (FULL MODEL + INFILTRATION + NON-CONDUIT ADIABATIC)
%% ================================================================
for jT = 2:m

    % Causal hydraulics from previous step (jT-1)
    Dw = Dus(jT-1, :);
    uw = Vus(jT-1, :);
    Qw = Qus(jT-1, :);

    % Keep depth within valid open-channel geometry range.
    % For dry-weather simulations this usually has no effect, but it prevents
    % numerical issues if any depth reaches or exceeds the pipe diameter.
    Dw = max(Dw, 1e-9);
    Dw = min(Dw, 2*0.99.*max(R,1e-9));

    % initialize current thermal state storage
    Tw_out(jT, :)        = NaN;
    Tw_in_before(jT, :)  = NaN;
    Tw_in_after(jT, :)   = NaN;

    % Geometry + hwa for this timestep
    b    = zeros(1,numberOfPipes);
    Larc = zeros(1,numberOfPipes);
    hwa  = zeros(1,numberOfPipes);

    for I = find(isConduit)
        if Dw(I) > 0
            hFr = fc(I) * uw(I) / sqrt(9.81 * Dw(I));
        else
            hFr = 0;
        end
        hwa(I) = hFr;

        sh = upper(string(Shapes{I}));
        switch sh
            case "C"
                [b(I), Larc(I)] = geom_circle(R(I), Dw(I));
            case "R"
                [b(I), Larc(I)] = geom_rectangular(R(I), Dw(I));
            case "E"
                [b(I), Larc(I)] = geom_egg(R(I), Dw(I));
            otherwise
                [b(I), Larc(I)] = geom_circle(R(I), Dw(I));
        end
    end

    dL = (L(:)./Mesh);
  
    Rwa = inf(numberOfPipes,1);   % Initialize wastewater-air thermal resistance 
    % infinite resistance or no heat exchange

    Rws = inf(numberOfPipes,1);   % Initialize wastewater-soil thermal resistance
    % infinite resistance or no heat exchange

    Rwa(isConduit) = Rwafun(hwa(isConduit), b(isConduit), dL(isConduit))';
    % Wastewater-to-air thermal resistance

    Rws(isConduit) = Rwsfun(t(isConduit), kp(isConduit), Larc(isConduit), ...
                        dL(isConduit), ksds(isConduit), b(isConduit))';
    % Wastewater-to-soil thermal resistance (pipe wall + soil)

  
    %% ------------------------------------------------
    %% Allocate node infiltration to downstream pipes
    %% ------------------------------------------------

    Qinf_pipe_t = zeros(1, numberOfPipes);   % Infiltration assigned to each pipe at current timestep

    for kk = 1:nInf

        % Pipes receiving flow from infiltration node kk
        pipesK = outPipesOfInfNode{kk};

        if isempty(pipesK)
            continue;   % No downstream pipes connected to this infiltration node
        end

        % Infiltration flow entering node kk [m3/s]
        Qk = Qinf_nodes(jT-1, kk);

        if Qk <= 0
            continue;   % No infiltration to allocate
        end

        % Total upstream flow in all receiving pipes
        Qsum = sum(Qus(jT-1, pipesK));

        if Qsum > 0

            % Distribute infiltration in proportion to pipe flow
            % Higher-flow pipes receive a larger share of the infiltration
            Qinf_pipe_t(pipesK) = Qinf_pipe_t(pipesK) + ...
            Qk * (Qus(jT-1, pipesK) / Qsum);

        else

            % Fallback: if all receiving pipe flows are zero,
            % split infiltration equally among the connected pipes
            Qinf_pipe_t(pipesK) = Qinf_pipe_t(pipesK) + ...
            Qk / numel(pipesK);

        end

    end
  
    % good practice: reset extraction histories for this timestep
    TinDrop(jT, :)     = 0;
    HexPowerExtracted(jT, :) = 0;


    % Solve in topological order
    for idx = 1:numel(topoOrder)
        I = topoOrder(idx);

        %% ------------------------------------------------
        %% Inlet temperature before heat losses/extraction
        %% ------------------------------------------------
        
        if isSource(I)
        
            % Source links receive wastewater directly from subcatchments
            Tin = Tw0(jT, I);
        
        else
        
            % ------------------------------------------------
            % Collect upstream inflows and temperatures
            % ------------------------------------------------
            ups = usLinkIndex{I};
        
            Q_up  = 0;   % Total upstream flow
            TQ_up = 0;   % Flow-weighted upstream temperature term
        
            for k = 1:numel(ups)
        
                upPipe = ups(k);
        
                % Flow leaving upstream pipe
                qk = Qds(jT-1, upPipe);
        
                % Upstream outlet temperature from current timestep
                tk = Tw_out(jT, upPipe);
        
                % Fallback to previous timestep if current value is unavailable
                if isnan(tk)
                    tk = Tw_out(jT-1, upPipe);
                end
        
                % Accumulate flow and heat contributions
                Q_up  = Q_up  + qk;
                TQ_up = TQ_up + qk * tk;
        
            end
        
            % ------------------------------------------------
            % Add local foul/trade inflows from subcatchment
            % ------------------------------------------------
            sc = SubcmPipeIndex(I);
        
            Q_loc  = 0;   % Local inflow
            TQ_loc = 0;   % Local heat contribution
        
            if sc > 0 && sc <= size(qfoul,2)
        
                % Divide subcatchment inflows if shared by multiple links
                share = 1;
        
                if ~isempty(scCounts) && sc <= numel(scCounts) && scCounts(sc) > 0
                    share = scCounts(sc);
                end
        
                % Foul and trade wastewater entering this link
                qf = qfoul(jT-1, sc) / share;
                qt = qtrade(jT-1, sc) / share;
        
                Q_loc  = qf + qt;
        
                % Flow-weighted local heat contribution
                TQ_loc = Tfoul(jT-1, sc)*qf + ...
                         Ttrade(jT-1, sc)*qt;
        
            end
        
            % ------------------------------------------------
            % Flow-weighted mixing temperature at pipe inlet
            % ------------------------------------------------
            Q_tot = Q_up + Q_loc;
        
            if Q_tot > 0
        
                % Mix upstream and local inflows using conservation of energy
                Tin = (TQ_up + TQ_loc) / Q_tot;
        
            else
        
                % Fallback if no flow is available
                if ~isnan(Tw0(jT,I))
        
                    Tin = Tw0(jT,I);
        
                else
        
                    % Final fallback: measured foul temperature profile
                    Tin = Tfoul_src(jT);
        
                end
        
            end
        
        end


        %% infiltration mixing at inlet
        Q_total = Qus(jT-1, I);
        Q_inf   = min(Qinf_pipe_t(I), Q_total);
        Q_other = max(Q_total - Q_inf, 0);

        if Q_total > 0
            Tin = (Q_other * Tin + Q_inf * Tinf) / Q_total;
        end

        Tw_in_before(jT, I) = Tin;

        %% ------------------------------------------------
        %% Heat extraction at pipe inlet
        %% ------------------------------------------------
        
        Tin_after = Tin;   % Default: no extraction, so inlet temperature is unchanged
        
        % Check whether the current pipe is one of the extraction pipes
        hexIdx = find(HexPipes == I, 1);
        
        if ~isempty(hexIdx)
        
            % Local flow available for extraction at this pipe
            Qloc = Qw(I);
        
            if Qloc > 0
        
                % Requested extraction power for this pipe and timestep [W]
                PowerRequested = HexPowerRequested(jT, hexIdx);
        
                % Temperature drop required to satisfy requested extraction
                dTRequested = PowerRequested / (rho * Qloc * cp);
        
                % Maximum allowable temperature drop before reaching Tmin
                dTMax = Tin - TminHex(hexIdx);
        
                if dTMax <= 0
        
                    % No extraction allowed because inlet temperature is already
                    % at or below the minimum permitted temperature
                    dTActual = 0;
                    PowerActual  = 0;
        
                else
        
                    % Actual temperature drop is limited by available heat
                    dTActual = min(dTRequested, dTMax);
        
                    % Actual extracted heat after applying temperature constraint [W]
                    PowerActual = rho * Qloc * cp * dTActual;
               
                end
        
                % Inlet temperature after extraction
                Tin_after = Tin - dTActual;
        
                % Store extraction results for this extraction pipe
                TinDrop(jT, hexIdx)     = dTActual;
                HexPowerExtracted(jT, hexIdx) = PowerActual;

        
            end
        end
        
        % Store inlet temperature after extraction for all links
        Tw_in_after(jT, I) = Tin_after;

        %% ------------------------------------------------
        %% Heat transfer along link
        %% ------------------------------------------------
        
        if ~isConduit(I)
        
            % Non-conduit links are treated as adiabatic
            % (no heat exchange with air or soil)
            Tw_out(jT, I) = Tin_after;
        
            % Uniform temperature profile along the link
            Tw_prof = Tin_after * ones(1, Mesh+1);
        
        else
        
            % Numerical floors to avoid divide-by-zero issues
            QwI  = max(Qw(I), 1e-4);
            RwaI = max(Rwa(I), 1e-6);
            RwsI = max(Rws(I), 1e-6);
        
            % Initialise longitudinal temperature profile
            Tw_prof = zeros(1, Mesh+1);
            Tw_prof(1) = Tin_after;   % Temperature at pipe inlet
        
            % March along the pipe length using Mesh segments
            for ii = 1:Mesh
        
                % Heat loss (or gain) to sewer air and surrounding soil
                Tw_prof(ii+1) = Tw_prof(ii) - ...
                    ( (1/RwaI)*(Tw_prof(ii) - Ta(jT,I)) + ...
                      (1/RwsI)*(Tw_prof(ii) - SoilTemp(jT,I)) ) ...
                    /(rho * QwI * cp);
        
                % Keep temperatures within a physically reasonable range
                %Tw_prof(ii+1) = max(min(Tw_next, 40), 0);
        
            end
        
            % Outlet temperature at the downstream end of the pipe
            Tw_out(jT, I) = Tw_prof(end);
        
        end
        
        % Store full longitudinal temperature profile for plotting
        Tw_mesh_plot_time(jT, I, :) = real(Tw_prof);

    end
end

% Extract temperature profiles at selected plotting timestep
Tw_mesh_plot = squeeze(Tw_mesh_plot_time(plotTimeIndex, :, :));

% We want one row per pipe.
% If squeeze() returns the matrix transposed, flip it.
% Ensure output dimensions match number of pipes
if size(Tw_mesh_plot,1) ~= numel(L)
    Tw_mesh_plot = Tw_mesh_plot.';
end

% Remove any small imaginary components from numerical calculations
Tw_mesh_plot = real(Tw_mesh_plot);

toc


%% ================================================================
%% Local helper for ID construction
%% ================================================================
function ids = build_ids_impl(hdr, tbl, cleanIDs)

    % Convert header to clean strings
    hdr = lower(strtrim(string(hdr)));

    % Locate columns explicitly
    us_idx  = find(hdr == "us_node_id", 1);
    suf_idx = find(hdr == "link_suffix", 1);

    if isempty(us_idx)
        error("Column 'us_node_id' not found in object table.");
    end

    if isempty(suf_idx)
        error("Column 'link_suffix' not found in object table.");
    end

    % Extract data
    us_nodes = tbl(:, us_idx);
    suffixes = tbl(:, suf_idx);

    n = size(tbl,1);
    ids = strings(n,1);

    for i = 1:n

        us = us_nodes{i};
        sf = suffixes{i};

        % Convert to string safely
        us = cleanIDs(string(us));

        if isnumeric(sf)
            sf = string(round(sf));
        else
            sf = cleanIDs(string(sf));
        end
      
        ids(i) = us + "." + sf;


    end

end


%% ========================= POST-PROCESSING ==============================

% ========================= TIME VECTOR =========================
timeVec = (0:m-1)';

nlast = 48;   % Use final 48 hours after repeated cycles/spin-up

validTime = length(timeVec)-nlast+1 : length(timeVec);

%========================= HEAT OPPORTUNITY =========================
Tmin_allowed = 5;   % °C minimum allowed discharge temperature

P_available = rho * cp .* Qus .* max(Tw_in_before - Tmin_allowed, 0); % upstream heat(inlet)
Pmean = mean(P_available(validTime,:), 1);                 % W
AvailabilityFraction = mean(P_available(validTime,:) > 0, 1);
P_out = rho * cp .* Qds .* max(Tw_out - Tmin_allowed, 0); % downstream heat (outlet)

%% ================================================================
%% EXPORT RESULTS BY SIMULATION MODE
%% ================================================================

LinkID   = pipe_header(:);
LinkType = linkType(:);
USnode   = pipeUSnode(:);
DSnode   = pipeDSnode(:);

BaseResults = table( ...
    LinkID, LinkType, USnode, DSnode, ...
    system_type, asset_id, conduit_length, shape, ...
    conduit_width, conduit_height, conduit_material, gradient);

%% ----------------------------------------------------------------
%% A) HEAT AVAILABILITY EXPORTS
%% ----------------------------------------------------------------
if doAvailability

    %% ---------------- Inlet heat ----------------
    HeatTable_In = array2table(P_available', ...
        'VariableNames', strcat("HeatIn_hr_", string(1:m)));

    Theat_In = [BaseResults HeatTable_In];
    writetable(Theat_In, fullfile(outputFolder,"Heat_Inlet_" + exportTag + ".csv"));

    %% ---------------- Outlet heat ----------------
    HeatTable_Out = array2table(P_out', ...
        'VariableNames', strcat("HeatOut_hr_", string(1:m)));

    Theat_Out = [BaseResults HeatTable_Out];
    writetable(Theat_Out, fullfile(outputFolder,"Heat_Outlet_" + exportTag + ".csv"));

    fprintf('Availability heat results exported\n');

    %% ---------------- Inlet temperature ----------------
    TempTable_In = array2table(Tw_in_before', ...
        'VariableNames', strcat("TempIn_hr_", string(1:m)));

    Ttemp_In = [BaseResults TempTable_In];
    writetable(Ttemp_In, fullfile(outputFolder,"Temperature_Inlet_" + exportTag + ".csv"));
    %% ---------------- Outlet temperature ----------------
    TempTable_Out = array2table(Tw_out', ...
        'VariableNames', strcat("TempOut_hr_", string(1:m)));

    Ttemp_Out = [BaseResults TempTable_Out];
    writetable(Ttemp_Out, fullfile(outputFolder,"Temperature_Outlet_" + exportTag + ".csv"));
    fprintf('Availability temperature results exported\n');

    %% ---------------- Inlet flow ----------------
    FlowTable_In = array2table(Qus', ...
        'VariableNames', strcat("FlowIn_hr_", string(1:m)));

    Tflow_In = [BaseResults FlowTable_In];
    writetable(Tflow_In, fullfile(outputFolder,"Flow_Inlet_" + exportTag + ".csv"));
    %% ---------------- Outlet flow ----------------
    FlowTable_Out = array2table(Qds', ...
        'VariableNames', strcat("FlowOut_hr_", string(1:m)));

    Tflow_Out = [BaseResults FlowTable_Out];
    writetable(Tflow_Out, fullfile(outputFolder,"Flow_Outlet_" + exportTag + ".csv"));
    fprintf('Availability flow results exported\n');

end

%% ----------------------------------------------------------------
%% B) HEAT EXTRACTION EXPORTS
%% ----------------------------------------------------------------
if doExtraction

    %% ---------------- Inlet temperature before extraction ----------------
    TempTable_Before = array2table(Tw_in_before', ...
        'VariableNames', strcat("TempInBefore_hr_", string(1:m)));

    Ttemp_Before = [BaseResults TempTable_Before];
    writetable(Ttemp_Before, fullfile(outputFolder,"Temperature_Inlet_BeforeExtraction_" + exportTag + ".csv"));

    %% ---------------- Inlet temperature after extraction ----------------
    TempTable_After = array2table(Tw_in_after', ...
        'VariableNames', strcat("TempInAfter_hr_", string(1:m)));

    Ttemp_After = [BaseResults TempTable_After];
    writetable(Ttemp_After, fullfile(outputFolder,"Temperature_Inlet_AfterExtraction_" + exportTag + ".csv"));

    %% ---------------- Outlet temperature ----------------
    TempTable_Out = array2table(Tw_out', ...
        'VariableNames', strcat("TempOut_hr_", string(1:m)));

    Ttemp_Out = [BaseResults TempTable_Out];
    writetable(Ttemp_Out, fullfile(outputFolder,"Temperature_Outlet_AfterExtraction_" + exportTag + ".csv"));

    fprintf('Extraction temperature results exported\n');

    %% ---------------- Extracted heat, extraction pipes only ----------------
    HexLinkID   = pipe_header(HexPipes);
    HexLinkType = linkType(HexPipes);
    HexUSnode   = pipeUSnode(HexPipes);
    HexDSnode   = pipeDSnode(HexPipes);

    Textract = table( ...
        HexLinkID(:), HexLinkType(:), HexUSnode(:), HexDSnode(:), ...
        TminHex(:), ...
        'VariableNames', {'LinkID','LinkType','USnode','DSnode','TminHex'});

    ExtractHeatTable = array2table(HexPowerExtracted', ...
        'VariableNames', strcat("ExtractedHeat_hr_", string(1:m)));

    Textract = [Textract ExtractHeatTable];

    writetable(Textract, fullfile(outputFolder,"Extracted_Heat_" + exportTag + ".csv"));

   fprintf('Extracted heat results exported\n');

end


   %%
          
    %%----very important to quickly get the index of the pipe----
    %I = find(strcmp(pipe_header, "TL21988401.1"))
    %pipe_header(I)


%% ===================Save Key Variables ==================================

save("SimulationVars_" + exportTag + ".mat", ...
     'Pmean','AvailabilityFraction','validTime','Tmin_allowed', ...
     'Tw_in_before','Tw_out','Tw_mesh_plot','plotTimeIndex', ...
     'topoOrder', ...
     'HexPipes','HexPowerRequested','TminHex','HexPowerExtracted','TinDrop');

fprintf('Simulation variables saved to SimulationVars_%s.mat\n', exportTag);


fprintf('\nPost-processing complete.\n');

