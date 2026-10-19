<?php

declare(strict_types=1);

// Runs at every start of the app container: makes .env (new secrets only the first time) and
// sets the values that belong to this Docker setup.
require '/app/vendor/autoload.php';

use System\Core\EnvFile;

$envFile = '/app/.env';

EnvFile::ensure($envFile, '/app/.env.example');

$domain = (string) getenv('DOMAIN');

$values = [
    'APP_URL'             => 'https://' . $domain,
    'TRUST_PROXY'         => 'true',
    'TRUSTED_PROXIES'     => (string) getenv('TRUSTED_PROXIES'),
];

EnvFile::set($envFile, $values);
