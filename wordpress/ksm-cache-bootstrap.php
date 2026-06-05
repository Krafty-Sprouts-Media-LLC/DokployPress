<?php
/**
 * Plugin Name: KSM Cache Bootstrap
 * Plugin URI:  https://github.com/Krafty-Sprouts-Media-LLC/WPDokploystack
 * Description: Must-use plugin for KSM WPDokploystack. Activates Redis Object
 *              Cache and MilliCache on the first web request after WordPress
 *              installation, so caching works without a manual redeploy.
 * Version:     1.0.0
 * Author:      Krafty Sprouts Media LLC
 * Author URI:  https://kraftysprouts.media
 *
 * @package    KSM-WPDokploystack
 * @subpackage CacheBootstrap
 * @since      1.8.0
 */

defined( 'ABSPATH' ) || exit;

/**
 * Bootstrap cache plugins if installed but not yet active.
 *
 * Complements the container entrypoint WP-CLI bootstrap — this fires on the
 * first HTTP request after the WordPress setup wizard completes.
 *
 * @since 1.0.0
 * @return void
 */
function ksm_cache_bootstrap_run() {
	static $ran = false;

	if ( $ran ) {
		return;
	}

	$ran = true;

	if ( ! function_exists( 'is_plugin_active' ) ) {
		require_once ABSPATH . 'wp-admin/includes/plugin.php';
	}

	$redis_plugin      = 'redis-cache/redis-cache.php';
	$millicache_plugin = 'millicache/millicache.php';

	if ( file_exists( WP_PLUGIN_DIR . '/redis-cache/redis-cache.php' ) && ! is_plugin_active( $redis_plugin ) ) {
		activate_plugin( $redis_plugin );
	}

	if ( file_exists( WP_PLUGIN_DIR . '/millicache/millicache.php' ) && ! is_plugin_active( $millicache_plugin ) ) {
		activate_plugin( $millicache_plugin );
	}

	if ( function_exists( 'exec' ) ) {
		$wp_path = escapeshellarg( ABSPATH );
		@exec( "wp redis enable --allow-root --path={$wp_path} 2>/dev/null" );
		@exec( "wp millicache drop --allow-root --path={$wp_path} 2>/dev/null" );
	}
}

add_action( 'plugins_loaded', 'ksm_cache_bootstrap_run', 1 );
