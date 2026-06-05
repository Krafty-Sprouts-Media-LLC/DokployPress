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
 * Version:     1.2.0
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
	 * Flag file set after a successful database search-replace.
	 *
	 * @since 1.2.0
	 * @var string
	 */
	const SEARCH_REPLACE_DONE_FLAG = WP_CONTENT_DIR . '/.ksm-search-replace-done';

	/**
	 * Stack-native cache plugins — always kept active on this stack.
	 *
	 * @since 1.1.0
	 * @var array
	 */
	const STACK_CACHE_PLUGINS = array(
		'redis-cache/redis-cache.php',
		'millicache/millicache.php',
	);

	/**
	 * Third-party cache plugins migrated from the source host.
	 * Deactivated on destination — Redis Object Cache + MilliCache replace them.
	 *
	 * @since 1.1.0
	 * @var array
	 */
	const CONFLICTING_CACHE_PLUGINS = array(
		'wp-super-cache/wp-cache.php',
		'w3-total-cache/w3-total-cache.php',
		'wp-rocket/wp-rocket.php',
		'litespeed-cache/litespeed-cache.php',
		'wp-fastest-cache/wpFastestCache.php',
		'hummingbird-performance/wp-hummingbird.php',
		'wp-optimize/wp-optimize.php',
		'comet-cache/comet-cache.php',
		'cache-enabler/cache-enabler.php',
		'swift-performance-lite/performance.php',
		'breeze/breeze.php',
		'sg-cachepress/sg-cachepress.php',
		'nginx-helper/nginx-helper.php',
		'powered-by-cache/pbc.php',
		'hyper-cache/plugin.php',
		'gator-cache/gator-cache.php',
		'wp-cloudflare-page-cache/wp-cloudflare-page-cache.php',
	);

	/**
	 * Plugins that must not be re-activated after migration cleanup.
	 *
	 * @since 1.1.0
	 * @var array
	 */
	const SKIP_PLUGINS = array(
		'migrate-guru/migrateguru.php',
	);

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
			return;
		}

		add_action( 'init', array( __CLASS__, 'run_post_migration_cleanup' ), 1 );
	}

	/**
	 * Execute all post-migration cleanup tasks.
	 *
	 * @since 1.0.0
	 * @return void
	 */
	public static function run_post_migration_cleanup() {
		if ( ! function_exists( 'is_plugin_active' ) ) {
			require_once ABSPATH . 'wp-admin/includes/plugin.php';
		}

		$log   = array();
		$log[] = '[' . gmdate( 'Y-m-d H:i:s' ) . '] KSM Migration Fixer — post-migration cleanup started.';

		self::flush_object_cache( $log );
		self::deactivate_conflicting_cache_plugins( $log );
		self::reconcile_cache_drop_ins( $log );
		self::run_database_search_replace( $log );
		self::fix_site_urls( $log );
		self::restore_plugins_from_database( $log );
		self::restore_theme_from_database( $log );
		self::ensure_stack_cache_plugins( $log );
		self::remove_migration_artefacts( $log );
		self::deactivate_migrate_guru( $log );

		flush_rewrite_rules( true );
		$log[] = '  ✅ Rewrite rules flushed.';

		self::flush_object_cache( $log );

		$marker = ABSPATH . self::MARKER_FILE;
		if ( file_exists( $marker ) ) {
			unlink( $marker );
			$log[] = '  ✅ Migration marker removed.';
		}

		$log[] = '[' . gmdate( 'Y-m-d H:i:s' ) . '] KSM Migration Fixer — cleanup complete.';
		$log[] = str_repeat( '-', 60 );

		file_put_contents( self::LOG_FILE, implode( PHP_EOL, $log ) . PHP_EOL, FILE_APPEND | LOCK_EX );
	}

	/**
	 * Flush WordPress object cache and delete hot option keys.
	 *
	 * @since 1.1.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function flush_object_cache( array &$log ) {
		if ( function_exists( 'wp_cache_flush' ) ) {
			wp_cache_flush();
		}

		wp_cache_delete( 'alloptions', 'options' );
		wp_cache_delete( 'active_plugins', 'options' );
		wp_cache_delete( 'template', 'options' );
		wp_cache_delete( 'stylesheet', 'options' );
		wp_cache_delete( 'siteurl', 'options' );
		wp_cache_delete( 'home', 'options' );

		$log[] = '  ✅ Object cache flushed (stale install state cleared).';
	}

	/**
	 * Deactivate third-party cache plugins — stack uses Redis + MilliCache only.
	 *
	 * @since 1.1.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function deactivate_conflicting_cache_plugins( array &$log ) {
		$deactivated = 0;

		foreach ( self::CONFLICTING_CACHE_PLUGINS as $plugin ) {
			$plugin_path = WP_PLUGIN_DIR . '/' . dirname( $plugin ) . '/' . basename( $plugin );

			if ( ! file_exists( $plugin_path ) ) {
				continue;
			}

			if ( is_plugin_active( $plugin ) ) {
				deactivate_plugins( $plugin, true );
				$log[] = '  ✅ Deactivated conflicting cache plugin: ' . $plugin;
				++$deactivated;
			}
		}

		if ( 0 === $deactivated ) {
			$log[] = '  — No conflicting cache plugins were active.';
		}
	}

	/**
	 * Remove drop-ins left by third-party cache plugins so stack plugins can own them.
	 *
	 * @since 1.1.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function reconcile_cache_drop_ins( array &$log ) {
		$object_cache = WP_CONTENT_DIR . '/object-cache.php';

		if ( file_exists( $object_cache ) && ! self::drop_in_belongs_to_stack( $object_cache, 'object' ) ) {
			unlink( $object_cache );
			$log[] = '  ✅ Removed foreign object-cache.php drop-in (Redis Object Cache will replace it).';
		}

		$advanced_cache = WP_CONTENT_DIR . '/advanced-cache.php';

		if ( file_exists( $advanced_cache ) && ! self::drop_in_belongs_to_stack( $advanced_cache, 'advanced' ) ) {
			unlink( $advanced_cache );
			$log[] = '  ✅ Removed foreign advanced-cache.php drop-in (MilliCache will replace it).';
		}
	}

	/**
	 * Check whether a drop-in file belongs to the stack cache plugins.
	 *
	 * @since 1.1.0
	 * @param string $file_path Absolute path to drop-in.
	 * @param string $type      Drop-in type: object|advanced.
	 * @return bool
	 */
	private static function drop_in_belongs_to_stack( $file_path, $type ) {
		$contents = file_get_contents( $file_path );

		if ( false === $contents ) {
			return false;
		}

		if ( 'object' === $type ) {
			return ( false !== stripos( $contents, 'redis-cache' ) || false !== stripos( $contents, 'Redis Object Cache' ) );
		}

		return ( false !== stripos( $contents, 'millicache' ) || false !== stripos( $contents, 'MilliCache' ) );
	}

	/**
	 * Run wp search-replace across all tables when the migrated URL differs from this stack.
	 * Skipped if the entrypoint already completed search-replace at container start.
	 *
	 * @since 1.2.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function run_database_search_replace( array &$log ) {
		if ( file_exists( self::SEARCH_REPLACE_DONE_FLAG ) ) {
			$log[] = '  — Database search-replace already completed at container start.';
			return;
		}

		$old_url = getenv( 'KSM_MIGRATION_OLD_URL' );
		if ( false === $old_url || '' === $old_url ) {
			$old_url = self::get_option_from_database( 'siteurl' );
		}

		$new_url = self::get_target_site_url();

		if ( empty( $old_url ) || empty( $new_url ) || $old_url === $new_url ) {
			$log[] = '  — Database search-replace skipped (URLs match or target URL unknown).';
			return;
		}

		if ( 0 === strpos( $old_url, 'https://' ) ) {
			$old_https = $old_url;
			$old_http  = 'http://' . substr( $old_url, 8 );
		} elseif ( 0 === strpos( $old_url, 'http://' ) ) {
			$old_http  = $old_url;
			$old_https = 'https://' . substr( $old_url, 7 );
		} else {
			$old_http  = 'http://' . $old_url;
			$old_https = 'https://' . $old_url;
		}

		if ( 0 === strpos( $new_url, 'https://' ) ) {
			$new_https = $new_url;
		} elseif ( 0 === strpos( $new_url, 'http://' ) ) {
			$new_https = 'https://' . substr( $new_url, 7 );
		} else {
			$new_https = 'https://' . $new_url;
		}

		$replacements = array(
			$old_https => $new_https,
			$old_http  => $new_https,
		);

		$old_host = wp_parse_url( $old_https, PHP_URL_HOST );
		$new_host = wp_parse_url( $new_https, PHP_URL_HOST );

		if ( $old_host && $new_host && $old_host !== $new_host ) {
			$replacements[ $old_host ] = $new_host;
		}

		if ( ! function_exists( 'exec' ) ) {
			$log[] = '  ⚠️  Database search-replace skipped (exec unavailable — entrypoint should have run this).';
			return;
		}

		$wp_path = escapeshellarg( ABSPATH );

		foreach ( $replacements as $from => $to ) {
			if ( $from === $to ) {
				continue;
			}

			$from_arg = escapeshellarg( $from );
			$to_arg   = escapeshellarg( $to );
			$command  = "wp search-replace {$from_arg} {$to_arg} --all-tables --skip-columns=guid --allow-root --path={$wp_path} 2>&1";

			$output = array();
			@exec( $command, $output );
			$log[] = '  ✅ search-replace: ' . $from . ' → ' . $to;
			if ( ! empty( $output ) ) {
				$log[] = '     ' . implode( PHP_EOL . '     ', array_slice( $output, 0, 3 ) );
			}
		}

		update_option( 'siteurl', $new_https );
		update_option( 'home', $new_https );

		touch( self::SEARCH_REPLACE_DONE_FLAG );
		$log[] = '  ✅ Database search-replace complete (HTTP fallback).';
	}

	/**
	 * Resolve the destination site URL from env or the current HTTP request.
	 *
	 * @since 1.2.0
	 * @return string
	 */
	private static function get_target_site_url() {
		$env_url = getenv( 'KSM_SITE_URL' );
		if ( false !== $env_url && '' !== $env_url ) {
			return untrailingslashit( $env_url );
		}

		$host = sanitize_text_field( wp_unslash( $_SERVER['HTTP_HOST'] ?? '' ) );
		if ( '' === $host ) {
			return '';
		}

		$protocol = is_ssl() ? 'https' : 'http';
		return $protocol . '://' . $host;
	}

	/**
	 * Align siteurl/home with the domain Dokploy is serving.
	 *
	 * @since 1.1.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function fix_site_urls( array &$log ) {
		$current_url = self::get_target_site_url();
		$stored_url  = self::get_option_from_database( 'siteurl' );

		if ( $stored_url && $current_url && $stored_url !== $current_url ) {
			update_option( 'siteurl', $current_url );
			update_option( 'home', $current_url );
			$log[] = "  ✅ siteurl/home updated: {$stored_url} → {$current_url}";
		} else {
			$log[] = "  — siteurl already correct: {$stored_url}";
		}
	}

	/**
	 * Re-activate plugins recorded in the migrated database.
	 *
	 * @since 1.1.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function restore_plugins_from_database( array &$log ) {
		$active_plugins = self::get_option_from_database( 'active_plugins' );

		if ( ! is_array( $active_plugins ) || empty( $active_plugins ) ) {
			$log[] = '  — No active_plugins list found in database.';
			return;
		}

		$skip_plugins = array_merge( self::SKIP_PLUGINS, self::CONFLICTING_CACHE_PLUGINS, self::STACK_CACHE_PLUGINS );
		$activated    = 0;
		$skipped      = 0;

		foreach ( $active_plugins as $plugin ) {
			if ( in_array( $plugin, $skip_plugins, true ) ) {
				++$skipped;
				continue;
			}

			$plugin_file = WP_PLUGIN_DIR . '/' . $plugin;

			if ( ! file_exists( $plugin_file ) ) {
				$log[] = '  ⚠️  Plugin file missing, skipped: ' . $plugin;
				continue;
			}

			if ( ! is_plugin_active( $plugin ) ) {
				$result = activate_plugin( $plugin, '', false, true );

				if ( is_wp_error( $result ) ) {
					$log[] = '  ⚠️  Could not activate ' . $plugin . ': ' . $result->get_error_message();
					continue;
				}

				$log[] = '  ✅ Re-activated plugin: ' . $plugin;
				++$activated;
			}
		}

		$log[] = "  — Plugin restore summary: {$activated} activated, {$skipped} skipped (migration/cache/stack).";
	}

	/**
	 * Activate the theme stored in the migrated database (not stale Redis / default theme).
	 *
	 * @since 1.1.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function restore_theme_from_database( array &$log ) {
		$stylesheet = self::get_option_from_database( 'stylesheet' );
		$template   = self::get_option_from_database( 'template' );

		if ( empty( $stylesheet ) ) {
			$log[] = '  — No stylesheet option in database; theme restore skipped.';
			return;
		}

		$theme_path = WP_CONTENT_DIR . '/themes/' . $stylesheet;

		if ( ! is_dir( $theme_path ) ) {
			$log[] = '  ⚠️  Theme directory missing: ' . $stylesheet;
			return;
		}

		$current_stylesheet = get_option( 'stylesheet' );

		if ( $current_stylesheet !== $stylesheet ) {
			switch_theme( $stylesheet );
			$log[] = "  ✅ Theme activated from database: {$current_stylesheet} → {$stylesheet} (template: {$template}).";
		} else {
			$log[] = '  — Theme already matches database: ' . $stylesheet;
		}
	}

	/**
	 * Ensure stack cache plugins are active and drop-ins are installed.
	 *
	 * @since 1.1.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function ensure_stack_cache_plugins( array &$log ) {
		$redis_plugin      = 'redis-cache/redis-cache.php';
		$millicache_plugin = 'millicache/millicache.php';

		if ( file_exists( WP_PLUGIN_DIR . '/redis-cache/redis-cache.php' ) ) {
			if ( ! is_plugin_active( $redis_plugin ) ) {
				activate_plugin( $redis_plugin );
				$log[] = '  ✅ Redis Object Cache plugin activated.';
			} else {
				$log[] = '  — Redis Object Cache already active.';
			}
		}

		if ( file_exists( WP_PLUGIN_DIR . '/millicache/millicache.php' ) ) {
			if ( ! is_plugin_active( $millicache_plugin ) ) {
				activate_plugin( $millicache_plugin );
				$log[] = '  ✅ MilliCache plugin activated.';
			} else {
				$log[] = '  — MilliCache already active.';
			}
		}

		if ( function_exists( 'exec' ) ) {
			$wp_path = escapeshellarg( ABSPATH );
			@exec( "wp redis enable --allow-root --path={$wp_path} 2>/dev/null" );
			@exec( "wp millicache drop --allow-root --path={$wp_path} 2>/dev/null" );
			$log[] = '  ✅ Redis/MilliCache drop-ins refreshed via WP-CLI.';
		}
	}

	/**
	 * Remove Migrate Guru receiver artefacts from the web root.
	 *
	 * @since 1.1.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function remove_migration_artefacts( array &$log ) {
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
	}

	/**
	 * Deactivate Migrate Guru on the destination after migration completes.
	 *
	 * @since 1.1.0
	 * @param array $log Log lines (by reference).
	 * @return void
	 */
	private static function deactivate_migrate_guru( array &$log ) {
		if ( is_plugin_active( 'migrate-guru/migrateguru.php' ) ) {
			deactivate_plugins( 'migrate-guru/migrateguru.php' );
			$log[] = '  ✅ Migrate Guru deactivated on destination (no longer needed here).';
		}
	}

	/**
	 * Read a wp_options value directly from the database, bypassing object cache.
	 *
	 * @since 1.1.0
	 * @param string $option_name Option name.
	 * @return mixed
	 */
	private static function get_option_from_database( $option_name ) {
		global $wpdb;

		$value = $wpdb->get_var(
			$wpdb->prepare(
				"SELECT option_value FROM {$wpdb->options} WHERE option_name = %s LIMIT 1",
				$option_name
			)
		);

		return maybe_unserialize( $value );
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

KSM_Migration_Fixer::init();
