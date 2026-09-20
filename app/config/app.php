<?php
declare(strict_types=1);

return [
    'env'          => getenv('APP_ENV') ?: 'production',
    'debug'        => (bool)(getenv('APP_DEBUG') ?: false),
    'name'         => getenv('APP_NAME') ?: 'School ERP',
    'url'          => rtrim((string)(getenv('APP_URL') ?: ''), '/'),
    'timezone'     => getenv('APP_TIMEZONE') ?: 'Asia/Kolkata',
    'key'          => getenv('APP_KEY') ?: '',
    'key_version'  => (int)(getenv('APP_KEY_VERSION') ?: 1),
    'session'      => [
        'name'             => getenv('SESSION_NAME') ?: 'SCHOOLERPSESSID',
        'idle_timeout'     => (int)(getenv('SESSION_IDLE_TIMEOUT') ?: 1800),
        'absolute_timeout' => (int)(getenv('SESSION_ABSOLUTE_TIMEOUT') ?: 28800),
    ],
    'impersonation' => [
        'ttl' => (int)(getenv('IMPERSONATION_TTL') ?: 1800),
    ],
    'csp_report_uri' => getenv('CSP_REPORT_URI') ?: '/csp-report.php',
    'trusted_proxies' => array_filter(array_map('trim', explode(',', (string)(getenv('TRUSTED_PROXIES') ?: '')))),
    'paths' => [
        'storage'  => dirname(__DIR__, 2) . '/storage',
        'sessions' => dirname(__DIR__, 2) . '/storage/sessions',
        'logs'     => dirname(__DIR__, 2) . '/storage/logs',
        'uploads'  => dirname(__DIR__, 2) . '/storage/uploads',
        'tmp'      => dirname(__DIR__, 2) . '/storage/tmp',
        'backups'  => dirname(__DIR__, 2) . '/storage/backups',
        'exports'  => dirname(__DIR__, 2) . '/storage/exports',
    ],
];