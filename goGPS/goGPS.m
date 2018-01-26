%--- * --. --- --. .--. ... * ---------------------------------------------
%               ___ ___ ___
%     __ _ ___ / __| _ | __
%    / _` / _ \ (_ |  _|__ \
%    \__, \___/\___|_| |___/
%    |___/                    v 0.6.0 alpha 1 - nightly
%
%--------------------------------------------------------------------------
%  Copyright (C) 2009-2017 Mirko Reguzzoni, Eugenio Realini
%  Originally written by:       Mirko Reguzzoni, Eugenio Realini
%  Contributors:                Gatti Andrea, Giulio Tagliaferro, ...
%  A list of all the historical goGPS contributors is in CREDITS.nfo
%--------------------------------------------------------------------------
%
%   This program is free software: you can redistribute it and/or modify
%   it under the terms of the GNU General Public License as published by
%   the Free Software Foundation, either version 3 of the License, or
%   (at your option) any later version.
%
%   This program is distributed in the hope that it will be useful,
%   but WITHOUT ANY WARRANTY; without even the implied warranty of
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%   GNU General Public License for more details.
%
%   You should have received a copy of the GNU General Public License
%   along with this program.  If not, see <http://www.gnu.org/licenses/>.
%
%--------------------------------------------------------------------------
% 01100111 01101111 01000111 01010000 01010011
%--------------------------------------------------------------------------

% clear all variables
% NOTE: using only 'clearvars' does not clear global variables, while using
% 'clear all' removes breakpoints
clearvars -global -except ini_settings_file use_gui; %  exceptions for goGPSgo
clearvars -except ini_settings_file use_gui; % exceptions for goGPSgo

% if the plotting gets slower than usual, there might be problems with the
% Java garbage collector. In case, you can try to use the following
% command:
%
% java.lang.System.gc() %clear the Java garbage collector
%
% or:
%
% clear java

%cd(fileparts(which('goGPS')));
%pwd

% close all the opened files
fclose('all');
flag_init_out = false;


% add all the subdirectories to the search path
if (~isdeployed)
    addpath(genpath(pwd));
end

% Init Core
core = Core.getInstance();
core.showTextHeader();

log = Logger.getInstance();

% Pointer to the global settings:
gs = Go_State.getInstance();
state = gs.getCurrentSettings();
%settings_file = checkPath('..\data\project\default_PPP\config\settings.ini');
if exist('ini_settings_file', 'var')
    state.importIniFile(ini_settings_file);
end

%----------------------------------------------------------------------------------------------
% INTERFACE TYPE DEFINITION
%----------------------------------------------------------------------------------------------

if exist('use_gui', 'var')
    mode_user = use_gui;
else
    mode_user =   1; % user interface type
    % mode_user = 0 --> use text interface
    % mode_user = 1 --> use GUI
end

% Init output interfaces (singletons)
w_bar = Go_Wait_Bar.getInstance(100,'Welcome to goGPS', 0);  % 0 means text, 1 means GUI, 5 both

%if mode_user == 1
%    w_bar.setOutputType(1); % 0 means text, 1 means GUI, 5 both
%else
w_bar.setOutputType(0); % 0 means text, 1 means GUI, 5 both
%end

% Kalman filter cannot be initialized when goGPS starts
kalman_initialized = false;

%----------------------------------------------------------------------------------------------
% INTERFACE STARTUP
%----------------------------------------------------------------------------------------------

% Set global variable for goGPS obj mode
clearvars -global goObj;

if (mode_user == 1)
    
    % Now there's a unique interface for goGPS
    % to be compatible among various OSs the property "unit" of all the
    % elements must be set to "pixels"
    % (default unit is "character", but the size of a character is OS dependent)
    [ok_go] = gui_goGPS;
    if (~ok_go)
        return
    end        
end

%-------------------------------------------------------------------------------------------
%% GO goGPS - here the computations start
%-------------------------------------------------------------------------------------------

log.newLine();
state.showTextMode();

gs.initProcessing(); % Set up / download observations and navigational files

cc = state.getConstellationCollector();

% start evaluating computation time
tic;

%-------------------------------------------------------------------------------------------
%% STARTING BATCH
%-------------------------------------------------------------------------------------------

% Starting batch!!!
f_ref_rec = state.getReferencePath();
num_ref_rec = numel(f_ref_rec);
f_trg_rec = state.getTargetPath();
num_trg_rec = numel(f_trg_rec);
num_session = numel(f_trg_rec{1});
f_mst_rec = state.getMasterPath();
num_mst_rec = numel(f_mst_rec);

% get short name for File_Name_Processor
fnp = File_Name_Processor();

initial_mode = state.getMode();
if num_session > 1
    is_batch = true;
    w_bar.setOutputType(0);
    %log.setColorMode(0);
else
    is_batch = false;
end

state.showTextMode();

sky = Core_Sky.getInstance();
for s = 1 : num_session
    %-------------------------------------------------------------------------------------------
    % SESSION START
    %-------------------------------------------------------------------------------------------
    
    fprintf('\n--------------------------------------------------------------------------\n');
    log.addMessage(sprintf('Starting session %d of %d', s, num_session));
    fprintf('--------------------------------------------------------------------------\n');
    
    % Init sky
    fr = File_Rinex(f_trg_rec{1}{s},100);
    cur_date_start = fr.first_epoch.last();
    cur_date_stop = fr.last_epoch.first();
    sky.initSession(cur_date_start, cur_date_stop);
        
    clear rec;  % handle to all the receivers
    clear mst;
    r = 0;
    for i = 1 : num_mst_rec
        log.newLine();
        log.addMessage(sprintf('Reading master %d of %d', i, num_mst_rec));
        fprintf('--------------------------------------------------------------------------\n\n');
        
        r = r + 1;
        mst(i) = Receiver(cc, f_mst_rec{i}{s}); %#ok<SAGROW>
        mst(i).preProcessing();
        rec(r) = mst(i);        
    end
    
    clear ref;
    for i = 1 : num_ref_rec
        log.newLine();
        log.addMessage(sprintf('Reading reference %d of %d', i, num_ref_rec));
        fprintf('--------------------------------------------------------------------------\n\n');
        
        r = r + 1;
        ref(i) = Receiver(cc, f_ref_rec{i}{s}); %#ok<SAGROW>
        ref(i).preProcessing();
        rec(r) = ref(i);        
    end
    
    clear trg;
    for i = 1 : num_trg_rec
        log.newLine();
        log.addMessage(sprintf('Reading target %d of %d', i, num_trg_rec));
        fprintf('--------------------------------------------------------------------------\n\n');
        
        r = r + 1;
        trg(i) = Receiver(cc, f_trg_rec{i}{s}); %#ok<SAGROW>        
        trg(i).preProcessing();
        rec(r) = trg(i);        
    end
    
    fprintf('--------------------------------------------------------------------------\n');
    log.newLine();
    log.addMarkedMessage('Syncing times, computing reference time');
    [p_time, id_sync] = Receiver.getSyncTime(rec, state.obs_type, state.getProcessingRate());
    
    for i = 1 : num_trg_rec
        trg(i).staticPPP(id_sync{i});
%         dt_i0 = trg(i).dt;
%         trg(i).applyDtRec(dt_i0);        
%         trg(i).staticPPP(id_sync{i});        
%         trg(i).dt = trg(i).dt + dt_i0;
    end
    
    trg_list(:,s) = trg;
end
    
