/* Saltstorm - 'Fun-Money' Betting on the Web
 * Copyright (C) 2013, 2014  Dustin Leavins
 *
 * Full license can be found in 'LICENSE.txt'
 */

var PaymentsController = ['$scope', '$window', function($scope, $window) {
    $scope.atMaxRank = function() {
        return $scope.currentRank >= $scope.maxRank;
    };
    $scope.rankup = function() {
       $.post('/api/payment', JSON.stringify({
            payment_type: 'rankup',
            amount: $scope.amount
        }))
        .done(function() {
            $scope.$apply(function() {
                $scope.insufficientFunds = false;
            });

            $window.alert('Gratz on your new rank');
        })
        .fail(function() {
            $scope.$apply(function() {
                $scope.insufficientFunds = true;
            });
        });

    };
}];

var FakeBetController = ['$scope', '$window', '$q', '$http', function($scope, $window, $q, $http) {
    $scope.showBettors = false;
    $scope.updateDelay = 5000; // 5 seconds
    $scope.betAmount = 0;
    $scope.bettingThisRound = false;
    $scope.betUpdateFailed = false;
    $scope.selectedParticipant = 'a';

    $.ajaxSetup({
      cache: false
    });

    $http.defaults.cache = null;
    
    $scope.winnerName = function() {
        if (!$scope.match || !$scope.match.winner) {
            return '';
        } else {
            return $scope.match
                .participants[$scope.match.winner]
                .name;
        }
    };

    $scope.hasManyParticipants = function() {
        if (!$scope.match) {
            return false;
        } else {
            return Object.keys($scope.match.participants).length > 2;
        }
    };

    $scope.submitBet = function(participantCode) {
        var betInvalid = (!$scope.betForm.$valid) ||
            ($scope.betAmount <= 0) ||
            ($scope.betAmount > $scope.account.balance);

        if (betInvalid) {
            $scope.betUpdateFailed = true;
            return;
        }

        $http.post('/api/bet', {
            forParticipant: participantCode,
            amount: $scope.betAmount
        })
        .success(function(data, status, headers, config) {
            $scope.bettingThisRound = true;
            $scope.betUpdateFailed = false;
        })
        .error(function(data, status, headers, config) {
            $window.console.log(data);
            $scope.betUpdateFailed = true;
        });
    };

    var updateAccountDataBody = function() {
        var deferred = $q.defer();

        $http.get('/api/account', { cache: false })
        .success(function(data, status, headers, config) {
            $scope.account = data;
            deferred.resolve();
        })
        .error(function(data, status, headers, config) {
            deferred.reject('Error');
        });

        return deferred.promise;
    }

    $scope.updateAccountData = function() {
        updateAccountDataBody();
    };

    var updateMatchDataBody = function(delay) {
        var deferred = $q.defer();
        
        $window.setTimeout(function() {
            $http.get('/api/current_match')
            .success(function(data, status, headers, config) {
                var previous_match_data = $scope.match;
                $scope.match = data;

                if (previous_match_data == null)
                {
                    $scope.betAmount = 0;
                    $scope.bettingThisRound = false;
                    $scope.betUpdateFailed = false;

                } else if (previous_match_data['status'] !== 'open' &&
                     data['status'] === 'open') {

                    $scope.betAmount = 0;
                    $scope.bettingThisRound = false;
                    $scope.betUpdateFailed = false;

                } else if (previous_match_data['status'] === 'inProgress' &&
                    data['status'] !== 'inProgress') {

                    if ($scope.betAmount != 0 && $scope.bettingThisRound) {
                        $scope.updateAccountData();
                    }

                    $scope.betAmount = 0;
                    $scope.bettingThisRound = false;
                    $scope.betUpdateFailed = false;

                }

                deferred.resolve();
            })
            .error(function(data, status, headers, config) {
                deferred.reject('Error');
            });
        }, delay);

        return deferred.promise;
    };

    $scope.updateMatchData = function(delay) {
        updateMatchDataBody(delay).then(function() {
            $scope.updateMatchData($scope.updateDelay);
        }, function() {
            alert('Error - no longer updating match data');
        });
    };

    $scope.updateAccountData();
    $scope.updateMatchData(0);
}];

