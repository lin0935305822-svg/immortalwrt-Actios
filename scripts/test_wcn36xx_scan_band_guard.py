#!/usr/bin/env python3
"""Exercise the real pinned RX band-selection and survey source before/after patch."""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import signal
import subprocess
import tempfile

try:
    import resource
except ImportError:
    raise SystemExit('Run this regression gate in Linux/WSL with a C compiler and patch.')

FIXTURE_SHA256 = '5749ed7fdc588e398e040f99b28b2ec995a363bd4a7e76ed5c89b18876236bd7'
SOURCE_PATH = Path('drivers/net/wireless/ath/wcn36xx/txrx.c')

PRELUDE = r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
typedef unsigned char u8;
enum { NL80211_BAND_2GHZ, NL80211_BAND_5GHZ };
struct ieee80211_channel { int center_freq; };
struct ieee80211_supported_band {
    struct ieee80211_channel *channels;
    int n_channels;
};
struct wiphy { struct ieee80211_supported_band *bands[2]; };
struct ieee80211_hw { struct wiphy *wiphy; };
struct survey { int rssi, snr; };
struct wcn36xx {
    struct ieee80211_hw *hw;
    struct survey chan_survey[64];
    int survey_lock, operating_band, operating_freq;
};
struct wcn36xx_rx_bd { unsigned int reserved0, rx_ch, rf_band, scan_learn; };
#define spin_lock(x) ((void)(x))
#define spin_unlock(x) ((void)(x))
#define add_device_randomness(p,n) ((void)(p), (void)(n))
#define get_snr(bd) ((void)(bd), 30)
#define WCN36XX_BAND(wcn) ((wcn)->operating_band)
#define WCN36XX_CENTER_FREQ(wcn) ((wcn)->operating_freq)
static int ieee80211_channel_to_frequency(int channel, int band)
{
    if (band == NL80211_BAND_2GHZ)
        return channel == 14 ? 2484 : 2407 + 5 * channel;
    return 5000 + 5 * channel;
}
'''

CASES = r'''
int main(int argc, char **argv)
{
    struct ieee80211_channel two_channels[14];
    struct ieee80211_channel five_channels[2] = {{5180}, {5720}};
    struct ieee80211_supported_band two = {two_channels, 14};
    struct ieee80211_supported_band five = {five_channels, 2};
    struct wiphy wiphy = {{&two, NULL}};
    struct ieee80211_hw hw = {&wiphy};
    struct wcn36xx wcn = {.hw=&hw, .operating_band=0, .operating_freq=2462};
    struct wcn36xx_rx_bd bd = {.scan_learn=1, .rx_ch=1, .rf_band=0};
    int channel, rf, frequency, count = 0;
    for (channel = 1; channel <= 14; channel++)
        two_channels[channel - 1].center_freq =
            ieee80211_channel_to_frequency(channel, NL80211_BAND_2GHZ);
    if (argc == 2 && strcmp(argv[1], "legacy-null") == 0) {
        exercise_rx_band(&wcn, &bd, &frequency);
        return 77; /* The vulnerable source must fault before reaching here. */
    }

    /* Valid 2.4 GHz scan channels must stay on the only registered band. */
    for (rf = 0; rf < 4; rf++) {
        for (channel = 1; channel <= 14; channel++) {
            bd.rf_band = rf;
            bd.rx_ch = channel;
            assert(exercise_rx_band(&wcn, &bd, &frequency) == NL80211_BAND_2GHZ);
            assert(frequency == two_channels[channel - 1].center_freq);
            count++;
        }
    }

    /* Keep the legacy mapping on radios that really register 5 GHz. */
    wiphy.bands[NL80211_BAND_5GHZ] = &five;
    for (rf = 0; rf < 4; rf++) {
        bd.rf_band = rf;
        bd.rx_ch = 1;
        assert(exercise_rx_band(&wcn, &bd, &frequency) == (rf == 1 ? 0 : 1));
        assert(frequency == (rf == 1 ? 2412 : 5180));
        count++;
    }
    bd.rf_band = 0;
    bd.reserved0 = 1;
    bd.rx_ch = 9; /* Encoded channel 25 maps to channel 144. */
    assert(exercise_rx_band(&wcn, &bd, &frequency) == NL80211_BAND_5GHZ);
    assert(frequency == 5720);
    count++;

    /* Reject a stale unsupported non-scan band before entering survey/RX. */
    bd.scan_learn = 0;
    wiphy.bands[NL80211_BAND_5GHZ] = NULL;
    wcn.operating_band = NL80211_BAND_5GHZ;
    assert(exercise_rx_band(&wcn, &bd, &frequency) == -1);
    count++;
    wcn.operating_band = NL80211_BAND_2GHZ;
    assert(exercise_rx_band(&wcn, &bd, &frequency) == NL80211_BAND_2GHZ);
    assert(frequency == 2462);
    count++;
    printf("WCN36xx RX band regression cases passed: %d\n", count);
    return 0;
}
'''


def actual_function(source, name):
    start = source.index('static void ' + name + '(')
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def harness(source):
    channel_map = re.search(r'static const u8 ab_rx_ch_map\[\] = \{.*?\};', source, re.S)
    if not channel_map:
        raise RuntimeError('Pinned channel map not found')
    begin = source.index('\tif (bd->scan_learn) {')
    end = source.index('\n\tif (bd->rate_id <', begin)
    # The code under test is copied from the actual vendor source, not rewritten.
    selection_and_survey = source[begin:end]
    wrapper = '''
static int exercise_rx_band(struct wcn36xx *wcn, struct wcn36xx_rx_bd *bd,
                            int *frequency)
{
    struct { int band, freq, signal; } status = {.signal=-45};
''' + selection_and_survey + '''
    *frequency = status.freq;
    return status.band;
drop:
    return -1;
}
'''
    return PRELUDE + channel_map.group(0) + '\n' + actual_function(source, 'wcn36xx_update_survey') + '\n' + wrapper + CASES


def no_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))



def test_build_integration(root):
    workflow = (root / '.github/workflows/Build_高通410 imm.yml').read_text()
    stage = workflow.split('    - name: Apply UFI003 WCN36xx scan band fix\n', 1)[1].split('    - name:', 1)[0]
    assert "if: ${{ inputs.profile == 'ufi003' }}" in stage
    assert 'ramoops_diag' not in stage
    assert 'scripts/apply_ufi003_wcn36xx_fix.sh' in stage
    assert 'install -m 0644 diagnostics/ufi003-panic-capture-window.patch' not in workflow
    verify = workflow.split('    - name: Verify compiled UFI003 WCN36xx source\n', 1)[1].split('    - name:', 1)[0]
    assert "inputs.profile == 'ufi003'" in verify
    assert '--prepared-source "$source"' in verify
    with tempfile.TemporaryDirectory(prefix='ufi003-patch-stage-') as name:
        source = Path(name)
        recipe = source / 'package/kernel/mac80211/Makefile'
        target = source / 'package/kernel/mac80211/patches/ath/996-wcn36xx-scan-band-guard.patch'
        target.parent.mkdir(parents=True)
        recipe_text = 'PKG_VERSION:=6.18.26\nPKG_HASH:=2ad578c6cae22f192fefd44e1449725228d4109ee781998b41dcbae872554968\n'
        recipe.write_text(recipe_text)
        def stage_patch(ok):
            result = subprocess.run(['/bin/sh', str(root / 'scripts/apply_ufi003_wcn36xx_fix.sh'), str(source)], capture_output=True, text=True)
            assert (result.returncode == 0) == ok, result.stdout + result.stderr
        stage_patch(True)
        stage_patch(True)  # Repeated staging must be safe.
        expected = (root / 'patches/wcn36xx-scan-band-guard.patch').read_bytes()
        assert target.read_bytes() == expected
        target.write_text('conflicting patch\n')
        stage_patch(False)
        assert target.read_text() == 'conflicting patch\n'
        target.unlink()
        recipe.write_text(recipe_text.replace('6.18.26', '6.18.27'))
        stage_patch(False)
        assert not target.exists()
        recipe.write_text(recipe_text.replace('2ad578c6', '00000000'))
        stage_patch(False)
        assert not target.exists()
    print('UFI003 workflow/staging regression passed (normal and diagnostic builds, fail-closed version/hash/conflict checks)')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path('.'))
    parser.add_argument('--prepared-source', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    fixture = root / 'tests/fixtures/backports-6.18.26' / SOURCE_PATH
    original = fixture.read_bytes()
    if hashlib.sha256(original).hexdigest() != FIXTURE_SHA256:
        raise RuntimeError('Pinned upstream fixture digest mismatch')
    patch = root / 'patches/wcn36xx-scan-band-guard.patch'
    with tempfile.TemporaryDirectory(prefix='ufi003-scan-regression-') as name:
        work = Path(name)
        target = work / SOURCE_PATH
        target.parent.mkdir(parents=True)
        target.write_bytes(original)
        applied = subprocess.run(['patch', '--batch', '--forward', '-p1', '-d', str(work), '-i', str(patch)], capture_output=True, text=True)
        if applied.returncode:
            raise RuntimeError(applied.stdout + applied.stderr)
        fixed = target.read_bytes()
        if args.prepared_source:
            if args.prepared_source.read_bytes() != fixed:
                raise RuntimeError('Compiled backports source does not match the reviewed fix')
            print('UFI003 compiled WCN36xx source matches reviewed scan fix')
            return
        # Exercise the exact CI source-verification interface in both directions.
        for candidate, success in [(target, True), (fixture, False)]:
            verified = subprocess.run(['python3', str(Path(__file__).resolve()), '--root', str(root), '--prepared-source', str(candidate)], capture_output=True, text=True)
            if (verified.returncode == 0) != success:
                raise RuntimeError(verified.stdout + verified.stderr)
        print('Compiled-source identity gate accepts patched source and rejects vulnerable source')
        test_build_integration(root)
        compiler = shutil.which('cc') or shutil.which('gcc')
        if not compiler:
            raise RuntimeError('A native C compiler is required in Linux/WSL')
        binaries = []
        for label, data in [('vulnerable', original), ('fixed', fixed)]:
            source = work / (label + '.c')
            binary = work / label
            source.write_text(harness(data.decode()))
            built = subprocess.run([compiler, '-std=gnu11', '-O0', '-Wall', '-Wextra', '-Werror', '-Wno-unused-label', str(source), '-o', str(binary)], capture_output=True, text=True)
            if built.returncode:
                raise RuntimeError(built.stdout + built.stderr)
            binaries.append(binary)
        legacy = subprocess.run([str(binaries[0]), 'legacy-null'], capture_output=True, preexec_fn=no_core)
        if legacy.returncode != -signal.SIGSEGV:
            raise RuntimeError(f'Vulnerable source did not reproduce the NULL fault: {legacy.returncode}')
        print('Pinned vulnerable source reproduced NULL survey dereference')
        fixed_run = subprocess.run([str(binaries[1])], capture_output=True, text=True, check=True)
        print(fixed_run.stdout, end='')


if __name__ == '__main__':
    main()
