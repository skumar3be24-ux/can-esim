# NGHDL model sources

**These are generated copies. Do not edit them — edit `vhdl/src/` instead.**

Comment-stripped duplicates of the files in `vhdl/src/`, used to build the
NGHDL code model that `spice/can_mixed.cir` instantiates.

## Why a separate copy

NGHDL's entity parser (`model_generation.py`) scans **every line** of the
uploaded file for the substrings `port` and `end`, including lines inside
comments. A comment containing either word corrupts the port scan and
produces the error:

    Please check the in/out direction of your port

Our `can_node_top.vhdl` header contained the phrase *"reformat the port
list"*, which started the scan inside the comment block. Stripping comments
avoids the whole class of problem.

## Regenerating

    cp vhdl/src/{crc15,bit_timing,bit_stuff,frame_gen,frame_rx,\
    can_tx_path,can_node,can_node_top}.vhdl nghdl_model/
    cd nghdl_model && python3 -c "
    import glob
    for fn in glob.glob('*.vhdl'):
        out=[l.split('--')[0].rstrip() for l in open(fn)]
        open(fn,'w').write('\n'.join(x for x in out if x.strip())+'\n')"

## Building the model

1. `python3 tools/patch_nghdl_multifile.py` (once — enables multi-file models)
2. Run `nghdl`
3. **Browse** → `can_node_top.vhdl`
4. **Add Files** → the other seven
5. **Upload**

Then `cd spice && ngspice -b can_mixed.cir`.
