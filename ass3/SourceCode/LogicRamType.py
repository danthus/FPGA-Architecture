from pulp import *
import numpy as np   

class LogicRamType:
    def __init__(self, circuit_id, logic_ram_id, width, depth, mode, lutram_config, bram_configs, problem):
        self.circuit_id = circuit_id
        self.logic_ram_id = logic_ram_id
        self.width = width
        self.depth = depth
        self.mode = mode
        
        self.lutram_best_config = self.optimal_configuration(lutram_config)
        self.bram_best_configs = [self.optimal_configuration(b_config) for b_config in bram_configs]
        
        # binary variables to select which type of RAM is used
        if(self.lutram_best_config[0]):
            self.logical_lutram = LpVariable(f"logical_lutram_{circuit_id}_{logic_ram_id}", cat='Binary')
        else:
            self.logical_lutram = 0 # prun invalid variable
            
        self.logical_brams = []
        for i in range(len(bram_configs)):
            if(self.bram_best_configs[0]):
                self.logical_brams.append(LpVariable(f"logical_bram_{circuit_id}_{logic_ram_id}_{i}", cat='Binary'))
            else:
                self.logical_brams.append(0) # prun invalid variable
            
        # only one type of ram can be used
        problem += (self.logical_lutram + lpSum(self.logical_brams)) == 1
        
        # calculate number of physical lutram, brams, extra LUTs based on which RAM is used.
        self.lutram_count = self.logical_lutram * self.lutram_best_config[0]
        self.bram_counts = [self.logical_brams[i] * self.bram_best_configs[i][0] for i in range(len(self.bram_best_configs))]
        self.extra_lut = self.logical_lutram * self.lutram_best_config[1] + lpSum([self.logical_brams[i] * self.bram_best_configs[i][1] for i in range(len(bram_configs))])
        
        
    # find best configuration (i.e. width, depth, parallel_count, series_count)for a given ram
    # keep in mind, connect in parallel requires no extra LUT
    # connect in series requires extra LUI
    # And maximum number of connection in series is 16
    # return parallel_count, series_count, optimal width, optimal depth, number of extra LUT
    def optimal_configuration(self, ram_config):
        if self.mode not in ram_config['mode']:
            return 0, 0, 0, 0, 0, 0
        range = len(ram_config['width']) if self.mode != 3 else len(ram_config['width']) - 1
        parallel_list = -(-self.width // np.array(ram_config['width'][:range])) # round up
        series_list = -(-self.depth // np.array(ram_config['depth'][:range])) # round up
        idx = np.argmin(parallel_list*series_list)
        parallel_count = parallel_list[idx]
        series_count = series_list[idx]
        if series_count >= 16:
            return 0, 0, 0, 0, 0, 0   # no optimal configuration
        
        extra_lut = self.compute_extra_lut(series_count, self.width)
        if(self.mode == 3):
            extra_lut *= 2 # double for TrueDualPort mode
        
        return parallel_count*series_count, extra_lut, parallel_count, series_count, ram_config['width'][idx], ram_config['depth'][idx]
    
    # connect in series requires extra LUTs
    # one is log2(R) : R decoder
    # one is R : 1 MUX with [width] number of copies
    def compute_extra_lut(self, series_count, width):
        if(series_count == 1):
            return 0 # no extra lut needed
        
        if series_count == 2:
            decoder_count = 1 # special case
        else:
            decoder_count = series_count
            
        if(series_count <= 4):
            R1mux_count = 1
        elif(series_count <= 8):
            R1mux_count = 3
        elif(series_count <= 12):
            R1mux_count = 4
        elif(series_count <= 16):
            R1mux_count = 5
            
        mux_count = width * R1mux_count        
        return decoder_count + mux_count
    
    # return final configuration in format: S P extra_lut TYPE W D
    def final_config(self):
        if(value(self.logical_lutram)):
            return self.lutram_best_config[3], self.lutram_best_config[2], self.lutram_best_config[1], 1, self.lutram_best_config[4], self.lutram_best_config[5]
        else:
            for i in range(len(self.logical_brams)):
                if(value(self.logical_brams[i])):
                    return self.bram_best_configs[i][3], self.bram_best_configs[i][2], self.bram_best_configs[i][1], i+2, self.bram_best_configs[i][4], self.bram_best_configs[i][5]
                
        return 0 # shouldn't get here