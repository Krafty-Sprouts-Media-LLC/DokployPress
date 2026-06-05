<?php
/**
 * Plugin Name: KSM Migration Fixer
 * Plugin URI:  https://github.com/Krafty-Sprouts-Media-LLC/WPDokploystack
 * Description: Must-use plugin for KSM WPDokploystack. Automatically runs
 *              WordPress-level post-migration cleanup after a migration tool
 *              (e.g. Migrate Guru) completes. Handles permalink flushing,
 *              Redis cache reconnection, migration artefact removal, and
 *              domain correction. Fires only when a migration completion
 *              marker is detected — zero overhead on normal requests.
 * Version:     1.0.0
 * Author:      Krafty Sprouts Media LLC
 * Author URI:  https://kraftysprouts.media
 *
 * This file is automatically deployed to wp-content/mu-plugins/ by the
 * WordPress container entrypoint on every container start, ensuring it
 * survives migration tool overwrites of wp-content.
 *
 * @package    KSM-WPDokploystack
 * @subpackage MigrationFixer
 * @since      1.7.0
 */

// Prevent direct file access.
defined( 'ABSPATH' ) || exit;

/**
 * KSM_Migration_Fixer
 *
 * Hooks into WordPress init to detect and handle post-migration state.
 * All actions are gated behind a marker file check so there is zero
 * performance impact on normal (non-migration) requests.
 */
class KSM_Migration_Fixer {

    /**
     * Marker file written by the migration tool (or our entrypoint) to
     * signal that a migration just completed and cleanup is needed.
     * Path relative to ABSPATH.
     *
     * @since 1.0.0
     * @var string
     */
    const MARKER_FILE = 'ksm-migration-pending.txt';

    /**
     * Log file for recording what was fixed.
     * Stored in wp-content so it persists across container restarts.
     *
     * @since 1.0.0
     * @var string
     */
    const LOG_FILE = WP_CONTENT_DIR . '/ksm-migration-fixer.log';

    /**
     * Boot the fixer — called once per request via mu-plugin auto-load.
     * Only registers hooks if the migration marker file is present.
     *
     * @since 1.0.0
     * @return void
     */
    public static function init() {
        $marker = ABSPATH . self::MARKER_FILE;

        if ( ! file_exists( $marker ) ) {
            return; // Nothing to do — normal request, exit immediately.
        }

        // Run cleanup after WordPress core is loaded but before themes/plugins.
        add_action( 'init', array( __CLASS__, 'run_post_migration_cleanup' ), 1 );
    }

    /**
     * Execute all post-migration cleanup tasks.
     * Runs once, removes the marker file so subsequent requests are unaffected.
     *
     * @since 1.0.0
     * @return void
     */
    public static function run_post_migration_cleanup() {
        $log = array();
        $log[] = '[' . date( 'Y-m-d H:i:s' ) . '] KSM Migration Fixer — post-migration cleanup started.';

        // ------------------------------------------------------------------
        // 1. Fix site URL / home URL to match this stack's domain
        //    Reads from the HTTP_HOST header — the domain Dokploy is serving.
        // ------------------------------------------------------------------
        $protocol    = is_ssl() ? 'https' : 'http';
        $current_url = $protocol . '://' . sanitize_text_field( wp_unslash( $_SERVER['HTTP_HOST'] ?? '' ) );
        $stored_url  = get_option( 'siteurl' );

        if ( $stored_url && $current_url && $stored_url !== $current_url ) {
            update_option( 'siteurl', $current_url );
            update_option( 'home',    $current_url );
            $log[] = "  ✅ siteurl/home updated: {$stored_url} → {$current_url}";
        } else {
            $log[] = "  — siteurl already correct: {$stored_url}";
        }

        // ------------------------------------------------------------------
        // 2. Flush rewrite rules (fixes 404s on all pages except front page)
        // ------------------------------------------------------------------
        flush_rewrite_rules( true );
        $log[] = '  ✅ Rewrite rules flushed.';

        // ------------------------------------------------------------------
        // 3. Flush Redis object cache
        //    Works whether Redis Object Cache plugin is active or not.
        // ------------------------------------------------------------------
        if ( function_exists( 'wp_cache_flush' ) ) {
            wp_cache_flush();
            $log[] = '  ✅ Object cache flushed.';
        }

        // ------------------------------------------------------------------
        // 4. Remove Migrate Guru migration receiver script from web root
        //    This file is left behind after migration and should not remain
        //    publicly accessible.
        // ------------------------------------------------------------------
        $migration_scripts = array(
            ABSPATH . 'migrategurupull.php',
            ABSPATH . 'mg_storage',
        );

        foreach ( $migration_scripts as $path ) {
            if ( file_exists( $path ) ) {
                self::recursive_remove( $path );
                $log[] = '  ✅ Removed migration artefact: ' . basename( $path );
            }
        }

        // ------------------------------------------------------------------
        // 5. Deactivate Migrate Guru on the destination if still active
        //    It was installed here only to receive the migration — it should
        //    not run on an ongoing basis on the destination site.
        // ------------------------------------------------------------------
        if ( is_plugin_active( 'migrate-guru/migrateguru.php' ) ) {
            deactivate_plugins( 'migrate-guru/migrateguru.php' );
            $log[] = '  ✅ Migrate Guru deactivated on destination (no longer needed here).';
        }

        // ------------------------------------------------------------------
        // 6. Ensure Redis Object Cache plugin is activated
        //    It may have been deactivated or its settings lost during migration.
        // ------------------------------------------------------------------
        $redis_plugin = 'redis-cache/redis-cache.php';
        if ( file_exists( WP_PLUGIN_DIR . '/redis-cache/redis-cache.php' ) ) {
            if ( ! is_plugin_active( $redis_plugin ) ) {
                activate_plugin( $redis_plugin );
                $log[] = '  ✅ Redis Object Cache plugin activated.';
            } else {
                $log[] = '  — Redis Object Cache already active.';
            }
        }

        // ------------------------------------------------------------------
        // 7. Ensure MilliCache is activated after migration
        //    Activation recreates the advanced-cache.php drop-in if missing.
        // ------------------------------------------------------------------
        $millicache_plugin = 'millicache/millicache.php';
        if ( file_exists( WP_PLUGIN_DIR . '/millicache/millicache.php' ) ) {
            if ( ! is_plugin_active( $millicache_plugin ) ) {
                activate_plugin( $millicache_plugin );
                $log[] = '  ✅ MilliCache plugin activated.';
            } else {
                $log[] = '  — MilliCache already active.';
            }
        }

        // ------------------------------------------------------------------
        // 8. Remove the migration marker file — cleanup must only run once.
        // ------------------------------------------------------------------
        $marker = ABSPATH . self::MARKER_FILE;
        if ( file_exists( $marker ) ) {
            unlink( $marker );
            $log[] = '  ✅ Migration marker removed.';
        }

        $log[] = '[' . date( 'Y-m-d H:i:s' ) . '] KSM Migration Fixer — cleanup complete.';
        $log[] = str_repeat( '-', 60 );

        // Write to log file for audit trail.
        file_put_contents( self::LOG_FILE, implode( PHP_EOL, $log ) . PHP_EOL, FILE_APPEND | LOCK_EX );
    }

    /**
     * Recursively remove a file or directory.
     *
     * @since 1.0.0
     * @param string $path Absolute path to file or directory.
     * @return void
     */
    private static function recursive_remove( $path ) {
        if ( is_dir( $path ) ) {
            $items = array_diff( scandir( $path ), array( '.', '..' ) );
            foreach ( $items as $item ) {
                self::recursive_remove( $path . DIRECTORY_SEPARATOR . $item );
            }
            rmdir( $path );
        } elseif ( file_exists( $path ) ) {
            unlink( $path );
        }
    }
}

// Boot the fixer.
KSM_Migration_Fixer::init();
