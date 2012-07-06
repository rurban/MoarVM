my $cur_plane = -1;
my $last_code = -1;
my $cur_idx   = 0;

my %planes;
my @pieces;

for lines("UNIDATA/UnicodeData.txt".IO) -> $entry {
    my ($code_str, $name, $gencat, $ccclass, $bidiclass, $decmptype,
        $num1, $num2, $num3, $bidimirrored, $u1name, $isocomment,
        $suc, $slc, $stc) = $entry.split(';');
    
    my $code  = :16($code_str);
    my $plane = $code +> 16;
    my $idx   = $code +& 0xFFFF;
    
    # Is this a plane transition? If so, update planes info.
    if $cur_plane != $plane {
        %planes{$plane} = [$cur_idx, 0];
        $cur_plane = $plane;
    }
    
    # Otherwise handle situation where there are gaps.
    else {
        if $last_code + 1 != $code {
            for $last_code ^..^ $code {
                @pieces[$cur_idx++] = "    \{ NULL, $_, $_, $_ \}";
                %planes{$cur_plane}[1]++;
            }
        }
    }
    
    # Emit codepoint information.
    @pieces[$cur_idx++] = 
        '    { "' ~ $name ~ '", ' ~
        :16($suc || $code_str) ~ ', ' ~
        :16($slc || $code_str) ~ ', ' ~
        :16($stc || $code_str) ~ " }";
    %planes{$cur_plane}[1]++;
    
    $last_code = $code;
}

# Emit prelude to the data file.
my $fh = open("src/strings/unicode.c", :w);
$fh.say('/* This file is generated by ucd2c.p6 from the Unicode database. */

#include "moarvm.h"
');

# Emit the planes table.
$fh.say('static MVMUnicodePlane MVM_unicode_planes[] = {');
for %planes.sort(*.key) -> $plane {
    $fh.say('    { ' ~ 
        $plane.value.[0] ~ ', ' ~
        $plane.value.[1] ~ ' },');
}
$fh.say("};

#define MVM_UNICODE_PLANES %planes.elems()
");

# Emit the codepoints table.
$fh.say('static MVMCodePoint MVM_unicode_codepoints[] = {');
$fh.say(@pieces.join(",\n"));
$fh.say('};

/* Looks up address of some codepoint information. */
MVMCodePoint * MVM_unicode_codepoint_info(MVMThreadContext *tc, MVMint32 codepoint) {
    MVMint32 plane = codepoint >> 16;
    MVMint32 idx   = codepoint & 0xFFFF;
    if (plane < MVM_UNICODE_PLANES)
        if (idx < MVM_unicode_planes[plane].num_codepoints)
            return &MVM_unicode_codepoints[
                MVM_unicode_planes[plane].first_codepoint + idx];
    return NULL;
}
');

# And we're done.
$fh.close();
