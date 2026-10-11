<?php

declare(strict_types=1);

/*
 * Builds an Android bootanimation.zip from one 1280x800 PNG, holding it until boot completes.
 * Android's bootanimation player requires entries to be STORED (uncompressed), so this writes the
 * zip format directly rather than depending on the zip extension.
 *
 * Usage: php make-bootanimation.php <frame.png> <out.zip>
 */

if ($argc !== 3) {
    fwrite(STDERR, "Usage: php {$argv[0]} <frame.png> <out.zip>\n");
    exit(1);
}

[$_, $framePath, $outPath] = $argv;

$frame = file_get_contents($framePath);
if ($frame === false) {
    fwrite(STDERR, "Cannot read {$framePath}\n");
    exit(1);
}

$entries = [
    'desc.txt'     => "1280 800 1\np 0 0 part0\n",
    'part0/'       => '',
    'part0/000.png' => $frame,
];

// Fixed DOS timestamp (1980-01-01 00:00) keeps output reproducible.
$dosTime = 0;
$dosDate = (0 << 9) | (1 << 5) | 1;

$body = '';
$central = '';

foreach ($entries as $name => $data) {
    $offset = strlen($body);
    $crc = $data === '' ? 0 : crc32($data);
    $size = strlen($data);
    $common = pack('vvvvvVVV', 10, 0, 0, $dosTime, $dosDate, $crc, $size, $size) . pack('v', strlen($name));

    $body .= pack('V', 0x04034b50) . $common . pack('v', 0) . $name . $data;

    $external = str_ends_with($name, '/') ? 0x10 : 0;
    $central .= pack('V', 0x02014b50) . pack('v', 20) . $common
        . pack('vvvvVV', 0, 0, 0, 0, $external, $offset) . $name;
}

$end = pack('VvvvvVVv', 0x06054b50, 0, 0, count($entries), count($entries), strlen($central), strlen($body), 0);

if (file_put_contents($outPath, $body . $central . $end) === false) {
    fwrite(STDERR, "Cannot write {$outPath}\n");
    exit(1);
}
