import configparser
from math import sqrt
from pulp import *
import numpy as np
from LogicRamType import LogicRamType
import os, time

mode_str2int = {
    'ROM': 0,
    'SinglePort': 1,
    'SimpleDualPort': 2,
    'TrueDualPort': 3,
}
mode_int2str = ['ROM', 'SinglePort', 'SimpleDualPort' ,'TrueDualPort']


def read_circuits():
    path = "logical_rams.txt"
    f = open(path)
    Num_Circuits = int(f.readline().split()[1])
    f.readline() # skip categories
    
    circuits = [[] for _ in range(Num_Circuits)]
    for line in f.readlines():
        circuitID, RamID, Mode, Depth, Width = line.split()
        circuits[int(circuitID)].append({'mode': mode_str2int[Mode], 'depth': int(Depth), 'width': int(Width)})
    f.close()
    
    path = "logic_block_count.txt"
    f = open(path)
    f.readline() #skip
    
    block_count = [0 for _ in range(Num_Circuits)]
    for line in f.readlines():
        circuitID, blocks = line.split()
        block_count[int(circuitID)] = int(blocks)
        
    f.close()
    return circuits, block_count

def read_ram_config():
    config = configparser.ConfigParser(inline_comment_prefixes="#")
    config.read('ram_config.txt')
    
    # read lutram configuration
    lutram_config = {}
    lutram_config['type'] = config['LUTRAM']['type']
    if lutram_config['type'] == 'LUTRAM':
        # achitecture with LUTRAM
        lutram_config['bit_size'] = int(config['LUTRAM']['bit_size'])
        lutram_config['availability'] = float(config['LUTRAM']['availability'])
        lutram_config['mode'] = np.array([int(val) for val in config['LUTRAM']['mode'].split(',')])
        lutram_config['width'] = np.array([int(val) for val in config['LUTRAM']['width'].split(',')])
        lutram_config['depth'] = lutram_config['bit_size'] // lutram_config['width']
        avg_logic_block_area = (35000 * (lutram_config['availability'] -1) + 40000) / lutram_config['availability']
        # bit size, width, depth check
        for val in lutram_config['width']*lutram_config['depth']:
            if val != lutram_config['bit_size']:
                print("LURAM config: Error in bit_size or width. Please double check")
                exit()
        
    else:
        # achitecture with no LUTRAM
        lutram_config['bit_size'] = -1
        lutram_config['availability'] = -1
        lutram_config['mode'] = np.array([-1])
        lutram_config['width'] = np.array([-1])
        lutram_config['depth'] = np.array([-1])
        avg_logic_block_area = 35000
    
    # read bram configuration, there are multiple bram configurations
    bram_configs = []
    for section in config.sections():
        if section != 'LUTRAM':
            if(config[section]['type'] != 'BRAM'):
                continue
            else:
                bram_config = {}
                bram_config['type'] = config[section]['type']
                bram_config['bit_size'] = int(config[section]['bit_size'])
                bram_config['availability'] = float(config[section]['availability'])
                bram_config['mode'] = np.array([int(val) for val in config[section]['mode'].split(',')])
                bram_config['width'] = np.array([int(val) for val in config[section]['width'].split(',')])
                bram_config['depth'] = bram_config['bit_size'] // bram_config['width']
                area = 9000 + 5*bram_config['bit_size'] + 90*sqrt(bram_config['bit_size']) + 1200*bram_config['width'][-1]
                bram_config['area'] = area
                bram_configs.append(bram_config)
                
                # bit size, width, depth check
                for val in bram_config['width']*bram_config['depth']:
                    if val != bram_config['bit_size']:
                        print("BRAM config: Error in bit_size or width. Please double check")
                        exit()
            
    return lutram_config, bram_configs, avg_logic_block_area

def solve_circuit(circuit_id, circuit, block_count, lutram_config, bram_configs, avg_logic_block_area):
    LB_size = 10
    
    problem = LpProblem("RamMappingProblem", LpMinimize)
    
    # Objective: minimize total area
    # total area is given by : total logic blocks * area + total brams A * area + total brams B * area + ...
    # Note about limiting resource, constraints needed
    final_logic_block = LpVariable('Final_logic_block', 0, None, LpInteger)
    final_brams = [LpVariable(f"Final_bram_{i}", 0, None, LpInteger) for i in range(len(bram_configs))]  
    problem += avg_logic_block_area*final_logic_block + lpSum([bram_configs[i]['area']*final_brams[i] for i in range(len(bram_configs))]), "MinimizeArea"
    
    # Start adding constraints
    # three types of factors, the maximum one is the limiting factor
    # logic blocks required by circuit LB + extra LB + LUTRAM, logic blocks required by LUTRAM, logic blocks required by each BRAM
    
    # add constraint for each logic ram 
    logic_rams = [LogicRamType(circuit_id, logic_ram_id, circuit[logic_ram_id]['width'], circuit[logic_ram_id]['depth'], \
            circuit[logic_ram_id]['mode'], lutram_config, bram_configs, problem) for logic_ram_id in range(len(circuit))]
    
    total_lutram_count = lpSum([logic_ram.lutram_count for logic_ram in logic_rams])
    total_bram_counts = []
    for i in range(len(bram_configs)):
        total_bram_counts.append(lpSum([logic_ram.bram_counts[i] for logic_ram in logic_rams]))
    total_extra_lut = lpSum([logic_ram.extra_lut for logic_ram in logic_rams])
    
    # add constraint for [logic blocks required by circuit LB + extra LB + LUTRAM]
    final_extra_LB = LpVariable('Final_extra_LB', 0, None, LpInteger) # convert extra_lut to extra LB
    problem += final_extra_LB >= total_extra_lut/LB_size # - LB_size
    problem += final_extra_LB <= total_extra_lut/LB_size + LB_size
    
    problem += final_logic_block >= block_count + final_extra_LB + total_lutram_count
    
    # add constraint for [logic blocks required by LUTRAM]
    problem += final_logic_block >= total_lutram_count*lutram_config['availability']
    
    # add constraint for [logic blocks required by each BRAM]
    for i in range(len(bram_configs)):
        problem += final_logic_block >= total_bram_counts[i]*bram_configs[i]['availability']
        # calculate the final brams based on the final logic blocks
        problem += final_brams[i]*bram_configs[i]['availability'] >= final_logic_block - bram_configs[i]['availability']
        problem += final_brams[i]*bram_configs[i]['availability'] <= final_logic_block # + bram_configs[i]['availability']
    
    problem.solve(PULP_CBC_CMD(msg=0, timeLimit=7))
    # print("Status:", LpStatus[problem.status])
    # for v in problem.variables():
    #     if("Final" in v.name):
    #         print(v.name, "=", v.varValue)
    # print("Final_lutram = ", value(total_lutram_count))
    area = avg_logic_block_area*final_logic_block.varValue + np.sum([bram_configs[i]['area']*final_brams[i].varValue for i in range(len(bram_configs))])
    return area, logic_rams

def generate_mapping_file(f, circuit_id, logic_rams):
    f.write(f"// -----------------------Circuit {circuit_id}-----------------------------\n")
    for logic_ram_id, logic_ram in enumerate(logic_rams):
        S, P, extra_lut, TYPE, W, D = logic_ram.final_config()
        f.write(f'{circuit_id} {logic_ram_id} {extra_lut} LW {logic_ram.width} LD {logic_ram.depth} ID {logic_ram_id} S {S} P {P} Type {TYPE} Mode {mode_int2str[logic_ram.mode]} W {W} D {D} \n')
        

def main():
    circuits, block_count = read_circuits()
    lutram_config, bram_configs, avg_logic_block_area = read_ram_config()
    
    if os.path.exists('mapping.txt'):
        os.remove('mapping.txt')
    f = open('mapping.txt', 'w')
    
    areas = []
    
    time_start = time.time()
    
    # iterate through all 69 circuits
    for i in range(len(circuits)):
        area, logic_rams = solve_circuit(i, circuits[i], block_count[i], lutram_config, bram_configs, avg_logic_block_area)
        print(f"Circuit {i} finished with area: {area}")
        areas.append(area)
        generate_mapping_file(f, i, logic_rams)
    
    print("Geometric Average: ", '{:.4e}'.format(np.exp(np.log(areas).mean())))
    print("Total time spent: ", round(time.time() - time_start, 2), 'Sec')
    
    f.close()

main()
