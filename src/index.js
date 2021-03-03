/* Saltstorm - 'Fun-Money' Betting on the Web
 * Copyright (C) 2013, 2014, 2021  Dustin Leavins
 *
 * Full license can be found in 'LICENSE.txt'
 */

import 'angular';
import 'angular-route';
import 'bootstrap/dist/css/bootstrap.css';
import './app.scss';

var saltstorm = angular.module('saltstorm', ['ngRoute']);

saltstorm.factory('authService', ['$http', function($http) {
    var service = {
        isRegistered: false,
        login: function(email, password) {
            var instance = this;

            return $http.post('/api/login', {
                email: email,
                password: password
            }).then(function(response) {
                // TODO: Set api key
                instance.isRegistered = true;
                return response.data;
            }, function(response) {
                // TODO: Unset api key
                instance.isRegistered = false;
                throw response.data;
            });
        }
    };

    return service;
}]);

saltstorm.config(['$routeProvider', '$locationProvider', function($routeProvider, $locationProvider) {
    $routeProvider
    .when('/', {
        templateUrl: '/angular/index.html',
    }).when('/register', {
        templateUrl: '/angular/register.html',
        controller: 'RegisterController'
    }).when('/login', {
        templateUrl: '/angular/login.html',
        controller: 'LoginController'
    }).when('/logout', {
        templateUrl: '/angular/logout.html',
        controller: 'LogoutController'
    }).when('/request_password_reset', {
        templateUrl: '/angular/request_password_reset.html',
        controller: 'RequestPasswordResetController'
    }).when('/main', {
        templateUrl: function(params) {
            // TODO: This should be handled w/o using params so other pages
            // can go back here
            if (params && params.mobile) {
                return '/angular/main_mobile.html';
            } else {
                return '/angular/main.html';
            }
        },
        controller: 'MainController'
    }).when('/admin', {
        templateUrl: function(params) {
            // TODO: This should be handled w/o using params so other pages
            // can go back here
            if (params && params.mobile) {
                return '/angular/admin_mobile.html';
            } else {
                return '/angular/admin.html';
            }
        },
        controller: 'AdminController'

    }).when('/payments', {
        templateUrl: '/angular/payments.html',
        controller: 'PaymentsController'
    }).when('/manage_account', {
        templateUrl: '/angular/manage_account.html',
        controller: 'ManageAccountController'
    }).otherwise({
        redirectTo: '/'
    });

    $locationProvider.hashPrefix("");
}]);

saltstorm.directive('betInfo', function() {
    return {
        restrict: 'E',
        templateUrl: '/angular/bet_info.html'
    };
});

saltstorm.directive('navbar', function() {
    return {
        restrict: 'E',
        templateUrl: '/angular/navbar.html',
    };
});

saltstorm.directive('adminControl', function() {
   return {
        restrict: 'E',
        templateUrl: '/angular/admin_control.html'
    };
});

saltstorm.controller('RegisterController', ['$scope', '$http', '$location', function($scope, $http, $location) {
    // TODO: Go to selectable main page after successful registration

    $scope.register = function() {
      $http.post('/api/register', {
          email: $scope.email,
          password: $scope.password,
          confirmPassword: $scope.confirmPassword,
          displayName: $scope.displayName
      }).then(function () {
        $scope.errorMsg = null;
      }, function(response) {
          $scope.errorMsg = response.data.error;
      });
    };
}]);


saltstorm.controller('LoginController', ['$scope', '$location', 'authService', function($scope, $location, authService) {
    $scope.login = function() {
        authService.login($scope.email, $scope.password)
        .then(function(data) {
            $scope.errorMsg = null;
            var destination;


            if (data.permissions.indexOf('admin') === -1 ) {
                destination = '/main';
            } else {
                destination = '/admin';
            }

            if ($scope.goToMobile) {
              destination += '?mobile=true';
            }

            $location.url(destination);
        },function(data) {
            $scope.errorMsg = data.error;
        });
    };
}]);

saltstorm.controller('LogoutController', ['$scope', '$http', '$location', function($scope, $http, $location) {
    $http.post('/api/logout', {})
    .then(function() {
        $location.url('/');
    }, function() {
        alert('Failure - not logged-out');
    });
}]);

saltstorm.controller('RequestPasswordResetController', ['$scope', '$http', '$location', function($scope, $http, $location) {
    $scope.requestReset = function() {
        $http.post('/api/request_password_reset', {
            email: $scope.email
        }).then(function() {
            alert('Password reset request has been sent to ' + $scope.email);
            $scope.errorMsg = null;
            $location.url('/');
        }, function(response) {
            $scope.errorMsg = response.data.error;
            alert('Failure');
        });
    };
}]);

saltstorm.controller('PaymentsController', ['$scope', '$http', '$window', function($scope, $http, $window) {
    $scope.atMaxRank = function() {
        return $scope.currentRank >= $scope.maxRank;
    };

    $scope.rankup = function() {
       $http.post('/api/payment', {
            payment_type: 'rankup',
            amount: $scope.amount
        }).then(function () {
            $scope.insufficientFunds = false;
            $window.alert('Gratz on your new rank');
        }, function() {
            // TODO: Ensure that the error indicates insufficient funds.
            $scope.insufficientFunds = true;
        });
    };

    var lock = {
        account: false,
        siteConfig: false
    };

    $http.get('/api/account')
    .then(function(response) {
        const data = response.data;
        $scope.currentRank = data.currentRank;
        $scope.amount = data.amountToNextRank;
        lock.account = true;
    }, function() {
        console.error('Error retrieving account info.');
    });

    $http.get('/api/site_config')
    .then(function(response) {
        const data = response.data;
        $scope.maxRank = data.maxRank;
        lock.siteConfig = true;
    }, function() {
        console.error('Error retrieving site config.');
    });

    $scope.ready = function() {
        return lock.account && lock.siteConfig;
    };
}]);

saltstorm.controller('AdminController', ['$scope', '$http', '$window', '$timeout', function($scope, $http, $window, $timeout) {
    $http.defaults.cache = false;
    var updateDelay = 5000;
    var stopUpdating = false;

    var updateBody = function(delay) {
        return $timeout(function() {
            $http.get('/api/current_match')
            .then(function(response) {
                const data = response.data;
                //Do not update info while admin is changing it
                if (!stopUpdating) {
                    $scope.matchData = data;
                }
            }, function(response) {
                throw response.data;
            });
        }, delay);
    };

    var updateMatchInfo = function(delay) {
        if (stopUpdating) {
            return;
        }

        updateBody(delay).then(function() {
            updateMatchInfo(updateDelay);
        }, function() {
            stopUpdating = true;
            alert('Error - no longer updating match data');
        });
    };

    $scope.pushMatchInfo = function() {
      // TODO: Check presence of winner on payout transition
      console.log($scope);
      if ($scope.matchData.status === 'open') {
          $scope.matchData.winner = null;
      }

      $http.put('/api/current_match', $scope.matchData)
      .then(function() {
          $scope.stopEditing();
          $scope.error = null;
      }, function(response) {
          const data = response.data;
          if (data) {
              $scope.error = data.error;
            } else {
                $window.alert('There was an error while updating match data. Please try again.');
            }
      });
    };

    $scope.$on('$routeChangeStart', function() {
        stopUpdating = true;
    });

    $scope.editMode = false;

    $scope.startEditing = function() {
        stopUpdating = true;
        $scope.editMode = true;

        $scope.originalStatus = $scope.matchData.status;

        var nextDict = {
            closed: 'open',
            open: 'inProgress',
            inProgress: 'payout'
        };

        $scope.nextStatus = nextDict[$scope.originalStatus];
    };

    $scope.stopEditing = function() {
        stopUpdating = false;
        updateMatchInfo(0);
        $scope.editMode = false;
    };

    $scope.editModeDisabled = function() {
        if (!$scope.matchData) {
            return false;
        }

        return $scope.matchData.status === 'payout';
    };

    updateMatchInfo(0);
}]);

saltstorm.controller('MainController', ['$scope', '$window', '$http', '$timeout', '$document', function($scope, $window, $http, $timeout, $document) {
    $http.defaults.cache = false;
    $scope.showBettors = false;
    $scope.updateDelay = 5000; // 5 seconds
    $scope.betAmount = 0;
    $scope.bettingThisRound = false;
    $scope.betUpdateFailed = false;
    $scope.selectedParticipant = 'a';
    $scope.mobile = $document.find('.main-video').length === 0;
    
    $scope.winnerName = function() {
        if (!$scope.match || !$scope.match.winner) {
            return '';
        }

        return $scope.match
            .participants[$scope.match.winner]
            .name;
    };

    $scope.userOdds = function() {
        var doNotShow = !$scope.bettingThisRound ||
            !$scope.match ||
            !$scope.match.participants;

        if (doNotShow) {
            return null;
        }

        var bettingOn = $scope.bettingThisRound;
        return $scope.match.participants[bettingOn].odds;
    };

    $scope.hasManyParticipants = function() {
        if (!$scope.match) {
            return false;
        }

        return Object.keys($scope.match.participants).length > 2;
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
        }).then(function() {
            $scope.bettingThisRound = participantCode;
            $scope.betUpdateFailed = false;
        }, function(response) {
            const data = response.data;
            $window.console.log(data);
            $scope.betUpdateFailed = true;
        });
    };

    $scope.updateAccountData = function() {
        $http.get('/api/account')
        .then(function(response) {
            $scope.account = response.data;
        });
    };

    var stopUpdating = false;

    var updateMatchDataBody = function(delay) {
        // setInterval would be dangerous to use here because this update
        // can take longer than the delay.
        // There was a link to MDN here, but they removed the relevant section
        // concerning 'dangerous usage' of setInterval.
        return $timeout(function() {
            return $http.get('/api/current_match')
            .then(function(response) {
                const data = response.data;

                var previous_match_data = $scope.match;
                $scope.match = data;

                if (!previous_match_data)
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

                    if ($scope.betAmount !== 0 && $scope.bettingThisRound) {
                        $scope.updateAccountData();
                    }

                    $scope.betAmount = 0;
                    $scope.bettingThisRound = false;
                    $scope.betUpdateFailed = false;

                }
            }, function(response) {
                const data = response.data;
                throw response.data;
            });
        }, delay);
    };

    $scope.updateMatchData = function(delay) {
        updateMatchDataBody(delay).then(function() {
            if (!stopUpdating) {
                $scope.updateMatchData($scope.updateDelay);
            }
        }, function() {
            alert('Error - no longer updating match data');
        });
    };

    $scope.$on('$routeChangeStart', function() {
        stopUpdating = true;
    });

    $scope.updateAccountData();
    $scope.updateMatchData(0);
}]);

saltstorm.controller('ManageAccountController', ['$scope', '$http', '$location', function($scope, $http, $location) {
    $scope.changePassword = function() {
        $http.post('/api/account/password', {
            password: $scope.newPassword,
            confirmPassword: $scope.confirmPassword
        }).then(function() {
            $scope.changePasswordErrorMsg = null;
            alert('Successfully changed password.');
        }, function(response) {
            $scope.changePasswordErrorMsg = response.data.error;
        });
    };

    $scope.changeInfo = function() {
        $http.post('/api/account/info', {
            password: $scope.currentPassword,
            email: $scope.email,
            displayName: $scope.displayName,
            postUrl: $scope.postUrl
        }).then(function() {
            $scope.changeInfoErrorMsg = null;
            alert('Successfully changed account info.');
        }, function() {
            $scope.changeInfoErrorMsg = response.data.error;
        });
    };

    var lock = {
      account: false
    };

    $http.get('/api/account')
    .then(function(response) {
        const data = response.data;

        $scope.email = data.email;
        $scope.displayName = data.displayName;
        $scope.postUrl = data.postUrl;

        $scope.original = {
            email: data.email,
            displayName: data.displayName,
            postUrl: data.postUrl
        };
        lock.account = true;
    }, function() {
        $location.url('/');
    });

    $scope.ready = function() {
        return lock.account;
    };
}]);
