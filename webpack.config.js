const fs = require('fs');
const path = require('path');
const yaml = require('yaml');
const HtmlWebpackPlugin = require('html-webpack-plugin');
const CopyPlugin = require('copy-webpack-plugin');

const siteConfig = yaml.parse(fs.readFileSync('config/site.yml', 'utf-8'));

module.exports = {
  entry: {
      index: './src/index.js',
  },
  plugins: [
      new HtmlWebpackPlugin({
          title: siteConfig.common.site_name,
          template: './src/index.html'
      }),
      new CopyPlugin({
        patterns: [
          { from: "src/img", to: "img" },
          { from: "src/robots.txt", to: "robots.txt" },
        ],
      }),
  ],
  output: {
    filename: '[name].[contenthash].js',
    path: path.resolve(__dirname, 'dist'),
    clean: true,
  },
  optimization: {
      moduleIds: 'deterministic',
      runtimeChunk: 'single',
      splitChunks: {
          cacheGroups: {
          vendor: {
              test: /[\\/]node_modules[\\/]/,
              name: 'vendors',
              chunks: 'all',
       },
     },
   },
  },
  module: {
    rules: [
      {
        test: /\.s[ac]ss$/i,
        use: [
          "style-loader",
          "css-loader",
          "sass-loader",
        ],
      },
      {
        test: /\.css$/,
        use: [
          'style-loader',
          'css-loader'
        ],
      },
      {
        test: /\.(ttf|eot|woff|woff2|svg)$/,
        type: 'asset/resource',
      },
    ]
  }
};