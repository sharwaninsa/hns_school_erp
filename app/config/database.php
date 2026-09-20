<?php
declare(strict_types=1);

return [
    'host'    => getenv('DB_HOST') ?: '127.0.0.1',
    'port'    => (int)(getenv('DB_PORT') ?: 3306),
    'name'    => getenv('DB_NAME') ?: 'school_erp',
    'user'    => getenv('DB_USER') ?: '',
    'pass'    => getenv('DB_PASS') ?: '',
    'charset' => getenv('DB_CHARSET') ?: 'utf8mb4',
];