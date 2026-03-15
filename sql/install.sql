CREATE TABLE IF NOT EXISTS `fish_missions` (
    `id` VARCHAR(50) NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `description` TEXT,
    `type` VARCHAR(20) NOT NULL,
    `cooldown_seconds` INT UNSIGNED NOT NULL DEFAULT 0,
    `npc` LONGTEXT NOT NULL,
    `params` LONGTEXT NOT NULL,
    `messages` LONGTEXT,
    `reward` LONGTEXT,
    `level_required` INT UNSIGNED NOT NULL DEFAULT 0,
    `prerequisites` LONGTEXT,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `sort_order` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `fish_mission_progress` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `char_id` VARCHAR(60) NOT NULL,
    `mission_id` VARCHAR(50) NOT NULL,
    `status` ENUM('available','active','complete','cancelled') NOT NULL DEFAULT 'available',
    `times_completed` INT UNSIGNED NOT NULL DEFAULT 0,
    `cooldown_until` INT UNSIGNED NOT NULL DEFAULT 0,
    `progress` LONGTEXT,
    `npc_id` VARCHAR(50),
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_char_mission` (`char_id`, `mission_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
